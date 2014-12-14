defmodule Decanter.DecisionGraph do
  defmacro __using__(_) do
    quote location: :keep do
      import Decanter.DecisionGraph
      @before_compile Decanter.DecisionGraph

      @nodes %{}
      @decisions %{}
      @handlers %{}

      defp handle_decision(ctx, result) do
        case result do
          true  -> {true, ctx}
          false -> {false, ctx}
          {true, ctx}  -> {true, ctx}
          {false, ctx} -> {false, ctx}
        end
      end
    end
  end

  defmacro __before_compile__(env) do
    nodes = Module.get_attribute(env.module, :nodes)
    entry_name = Module.get_attribute(env.module, :entry_point)

    counts = visit_nodes(env.module, entry_name, nodes, %{})

    {rewritten_entry_name, r} = compile_decision(env.module, entry_name, {counts, nodes}, %{})
    # IO.inspect {"done", entry_name}
    fn_bodies = for {_, body} <- r do
      # IO.puts Macro.to_string(body)
      body
    end

    if entry_name != rewritten_entry_name do
      fn_bodies = [quote do
        defp do_decide(unquote(entry_name), ctx) do
          do_decide(unquote(rewritten_entry_name), ctx)
        end
      end|fn_bodies]
    end

    fn_bodies
  end

  defp visit_nodes(module, name, nodes, acc) do
    if acc[name] do
      Map.put(acc, name, acc[name] + 1)
    else
      case nodes[name] do
        {:branch, test, consequent, alternate} ->
          case Module.get_attribute(module, :decisions)[test] do
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
        {:branch, test, consequent, alternate} ->
          case Module.get_attribute(module, :decisions)[test] do
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

  defmacro branch(name, test, consequent, alternate) do
    quote do
      @nodes Map.put(@nodes, unquote(name), {:branch, unquote(test), unquote(consequent), unquote(alternate)})
    end
  end

  defmacro decide(name, args) do
    quote do
      @decisions Map.put(@decisions, unquote(name),
                                     unquote(Macro.escape(args[:do], unquote: true)))
    end
  end

  defmacro decision(name, consequent, alternate) do
    quote do
      branch unquote(name), unquote(name), unquote(consequent), unquote(alternate)
    end
  end

  defmacro decision(name, consequent, alternate, args) do
    quote do
      decide unquote(name), unquote(args)
      branch unquote(name), unquote(name), unquote(consequent), unquote(alternate)
    end
  end

  defmacro handler(name, status, content) do
    quote do
      @nodes Map.put(@nodes, unquote(name), {:handler, unquote(status), unquote(content)})
    end
  end

  defmacro action(name, next) do
    quote do
      @nodes Map.put(@nodes, unquote(name), {:action, unquote(next)})
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
