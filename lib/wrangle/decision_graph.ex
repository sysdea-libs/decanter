defmodule Wrangle.DecisionGraph do
  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Wrangle.DecisionGraph

      @nodes %{}
      @decisions %{}
      @handlers %{}

      defp dispatch_decision(conn, result, consequent, alternate) do
        case result do
          true  -> do_decide(consequent, conn)
          false -> do_decide(alternate, conn)
          {true, assigns}  -> do_decide(consequent, %{conn | assigns: Map.merge(conn.assigns, assigns)})
          {false, assigns} -> do_decide(alternate, %{conn | assigns: Map.merge(conn.assigns, assigns)})
        end
      end

      defp delete!(conn) do end
      defp post!(conn) do end
      defp put!(conn) do end
      defp patch!(conn) do end
    end
  end

  defmacro __before_compile__(env) do
    nodes = Module.get_attribute(env.module, :nodes)
    {entry_name, entry_body} = Module.get_attribute(env.module, :entry_point)
    {entry_name, r} = compile_decision(env.module, entry_name, nodes, %{})
    # IO.inspect {"done", root}
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

  defp compile_decision(module, name, nodes, bodies) do
    if bodies[name] do
      {name, bodies}
    else
      case nodes[name] do
        {:decision, consequent, alternate} ->
          case Module.get_attribute(module, :decisions)[name] do
            true -> compile_decision(module, consequent, nodes, bodies)
            false -> compile_decision(module, alternate, nodes, bodies)
            body ->
              {consequent, bodies} = compile_decision(module, consequent, nodes, bodies)
              {alternate, bodies} = compile_decision(module, alternate, nodes, bodies)

              body = quote location: :keep do
                defp do_decide(unquote(name), var!(conn)) do
                  dispatch_decision(var!(conn), unquote(body), unquote(consequent), unquote(alternate))
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
          {next, bodies} = compile_decision(module, next, nodes, bodies)

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
