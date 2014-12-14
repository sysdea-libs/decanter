defmodule Wrangle.DecisionGraph do
  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Wrangle.DecisionGraph

      @nodes %{}
      @decisions %{}
      @handlers %{}

      defp handle_decision(conn, result) do
        case result do
          true  -> {true, conn}
          false -> {false, conn}
          {true, assigns}  -> {true, %{conn | assigns: Map.merge(conn.assigns, assigns)}}
          {false, assigns} -> {false, %{conn | assigns: Map.merge(conn.assigns, assigns)}}
        end
      end
    end
  end

  defmacro __before_compile__(env) do
    nodes = Module.get_attribute(env.module, :nodes)
    {entry_name, entry_body} = Module.get_attribute(env.module, :entry_point)

    counts = visit_nodes(env.module, entry_name, nodes, %{})

    {entry_name, r} = compile_decision(env.module, entry_name, {counts, nodes}, %{})
    # IO.inspect {"done", entry_name}
    fn_bodies = for {_, body} <- r do
      # IO.puts Macro.to_string(body)
      body
    end

    serve = quote do
      def serve(var!(conn), opts) do
        var!(root) = unquote(entry_name)
        unquote(entry_body)
      end
    end

    [fn_bodies, serve]
  end

  defp visit_nodes(module, name, nodes, acc) do
    if acc[name] do
      Map.put(acc, name, acc[name] + 1)
    else
      case nodes[name] do
        {:decision, consequent, alternate} ->
          case Module.get_attribute(module, :decisions)[name] do
            true -> visit_nodes(module, consequent, nodes, acc)
            false -> visit_nodes(module, alternate, nodes, acc)
            _body ->
              acc = visit_nodes(module, consequent, nodes, acc)
              acc = visit_nodes(module, alternate, nodes, acc)
              if acc[name] do
                Map.put(acc, name, acc[name] + 1)
              else
                Map.put(acc, name, 1)
              end
          end
        {:dispatch, _conn_match, handles} ->
          Enum.reduce(handles, acc, fn([_, branch], acc) ->
            visit_nodes(module, branch, nodes, acc)
          end)
        {:handler, _status, _content} ->
          if acc[name] do
            Map.put(acc, name, acc[name] + 1)
          else
            Map.put(acc, name, 1)
          end
        {:action, next} ->
          acc = visit_nodes(module, next, nodes, acc)
          if acc[name] do
            Map.put(acc, name, acc[name] + 1)
          else
            Map.put(acc, name, 1)
          end
      end
    end
  end

  defp compile_decision(module, name, {counts, nodes}=cnodes, bodies) do
    if bodies[name] do
      {name, bodies}
    else
      case nodes[name] do
        {:decision, consequent, alternate} ->
          case Module.get_attribute(module, :decisions)[name] do
            true -> compile_decision(module, consequent, cnodes, bodies)
            false -> compile_decision(module, alternate, cnodes, bodies)
            body ->
              {consequent, bodies} = compile_decision(module, consequent, cnodes, bodies)
              {alternate, bodies} = compile_decision(module, alternate, cnodes, bodies)
              same_path = consequent == alternate

              if counts[consequent] == 1 || (same_path && counts[consequent] == 2) do
                {:defp, _, [{:do_decide, _, _},[{:do, x}]]} = bodies[consequent]
                consequent_body = x
                bodies = Map.delete(bodies, consequent)
              else
                consequent_body = quote do
                  do_decide(unquote(consequent), var!(conn))
                end
              end

              if counts[alternate] == 1 do
                {:defp, _, [{:do_decide, _, _},[{:do, x}]]} = bodies[alternate]
                alternate_body = x
                bodies = Map.delete(bodies, alternate)
              else
                alternate_body = quote do
                  do_decide(unquote(alternate), var!(conn))
                end
              end

              strategy = case body do
                {:==, _, _} -> :if
                {:in, _, _} -> :if
                {:has_header, _, _} -> :if
                _ -> :case
              end

              body = case {same_path, strategy} do
                {true, :if} ->
                  quote location: :keep do
                    defp do_decide(unquote(name), var!(conn)) do
                      unquote(consequent_body)
                    end
                  end
                {true, :case} ->
                  quote location: :keep do
                    defp do_decide(unquote(name), var!(conn)) do
                      {_, var!(conn)} = handle_decision(var!(conn), unquote(body))
                      unquote(consequent_body)
                    end
                  end
                {false, :if} ->
                  quote location: :keep do
                    defp do_decide(unquote(name), var!(conn)) do
                      if unquote(body) do
                        unquote(consequent_body)
                      else
                        unquote(alternate_body)
                      end
                    end
                  end
                {false, :case} ->
                  quote location: :keep do
                    defp do_decide(unquote(name), var!(conn)) do
                      case handle_decision(var!(conn), unquote(body)) do
                        {true, var!(conn)} -> unquote(consequent_body)
                        {false, var!(conn)} -> unquote(alternate_body)
                      end
                    end
                  end
              end

              {name, Map.put(bodies, name, body)}
            end
        {:dispatch, conn_match, cases} ->
          {handles, bodies} = Enum.map_reduce(cases, bodies, fn ([match, branch], bodies) ->
            {branch, bodies} = compile_decision(module, branch, cnodes, bodies)
            c = quote do
              unquote(match) -> unquote(branch)
            end
            {c, bodies}
          end)

          body = quote location: :keep do
            defp do_decide(unquote(name), var!(conn)) do
              do_decide(case unquote(conn_match) do
                unquote(handles |> List.flatten)
              end, var!(conn))
            end
          end

          {name, Map.put(bodies, name, body)}
        {:handler, status, content} ->
          handlers = Module.get_attribute(module, :handlers)

          if Map.has_key?(handlers, name) do
            handles = for {match,body} <- Enum.reverse(handlers[name]) do
              quote do
                unquote(match) -> unquote(body)
              end
            end

            body = quote location: :keep do
              defp do_decide(unquote(name), var!(conn)) do
                content = case var!(conn) do
                  unquote(handles |> List.flatten)
                end

                Plug.Conn.resp(var!(conn), unquote(status), content)
              end
            end
          else
            body = quote location: :keep do
              defp do_decide(unquote(name), var!(conn)) do
                Plug.Conn.resp(var!(conn), unquote(status), unquote(content))
              end
            end
          end

          {name, Map.put(bodies, name, body)}
        {:action, next} ->
          {next, bodies} = compile_decision(module, next, cnodes, bodies)

          body = quote location: :keep do
            defp do_decide(unquote(name), var!(conn)) do
              do_decide(unquote(next), unquote(name)(var!(conn)))
            end
          end

          {name, Map.put(bodies, name, body)}
      end
    end
  end

  defmacro decision(name, consequent, alternate) do
    quote do
      @nodes Map.put(@nodes, unquote(name), {:decision, unquote(consequent), unquote(alternate)})
    end
  end

  defmacro decision(name, consequent, alternate, args) do
    quote do
      @decisions Map.put(@decisions, unquote(name),
                                     unquote(Macro.escape(args[:do], unquote: true)))
      @nodes Map.put(@nodes, unquote(name), {:decision, unquote(consequent), unquote(alternate)})
    end
  end

  defmacro handler(name, status, content) do
    quote do
      @nodes Map.put(@nodes, unquote(name), {:handler, unquote(status), unquote(content)})
    end
  end

  defmacro dispatch(name, conn_match, mapping) do
    quote do
      @nodes Map.put(@nodes, unquote(name),
                      {:dispatch, unquote(Macro.escape(conn_match, unquote: true)),
                                  unquote(Macro.escape(mapping, unquote: true))})
    end
  end

  defmacro entry_point(name, args) do
    quote do
      @entry_point {unquote(name), unquote(Macro.escape(args[:do], unquote: true))}
    end
  end

  defmacro action(name, next) do
    quote do
      @nodes Map.put(@nodes, unquote(name), {:action, unquote(next)})
    end
  end

  defmacro decide(name, args) do
    quote do
      @decisions Map.put(@decisions, unquote(name),
                                     unquote(Macro.escape(args[:do], unquote: true)))
    end
  end

  defmacro handle(name, conn, args) do
    name = String.to_atom("handle_" <> (name |> to_string))

    quote do
      entry = {unquote(Macro.escape(conn, unquote: true)),
               unquote(Macro.escape(args[:do], unquote: true))}

      if existing = @handlers[unquote(name)] do
        @handlers Map.put(@handlers, unquote(name), [entry|existing])
      else
        @handlers Map.put(@handlers, unquote(name), [entry])
      end
    end
  end
end
