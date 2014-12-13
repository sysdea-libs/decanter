defmodule Wrangle.DecisionGraph do
  defmacro __using__(_) do
    quote location: :keep do
      import Wrangle.DecisionGraph

      @before_compile Wrangle.DecisionGraph
      @nodes %{}

      defp handle(conn, result, consequent, alternate) do
        case result do
          true  -> decide(consequent, conn)
          false -> decide(alternate, conn)
          {true, assigns}  -> decide(consequent, %{conn | assigns: Map.merge(conn.assigns, assigns)})
          {false, assigns} -> decide(alternate, %{conn | assigns: Map.merge(conn.assigns, assigns)})
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
        {:decision, consequent, alternate, body} ->
          case {Module.defines?(module, {name, 1}), body} do
            {false, true} -> compile_decision(module, consequent, nodes, bodies)
            {false, false} -> compile_decision(module, alternate, nodes, bodies)
            {true, _} ->
              {consequent, bodies} = compile_decision(module, consequent, nodes, bodies)
              {alternate, bodies} = compile_decision(module, alternate, nodes, bodies)

              body = quote location: :keep do
                defp decide(unquote(name), var!(conn)) do
                  handle(var!(conn), unquote(name)(var!(conn)), unquote(consequent), unquote(alternate))
                end
              end

              {name, Map.put(bodies, name, body)}
            {false, _} ->
              {consequent, bodies} = compile_decision(module, consequent, nodes, bodies)
              {alternate, bodies} = compile_decision(module, alternate, nodes, bodies)

              body = quote location: :keep do
                defp decide(unquote(name), var!(conn)) do
                  handle(var!(conn), unquote(body), unquote(consequent), unquote(alternate))
                end
              end

              {name, Map.put(bodies, name, body)}
            end
        {:handler, status, content} ->
          defined = Module.defines?(module, {name, 1})

          if defined do
            body = quote location: :keep do
              defp decide(unquote(name), var!(conn)) do
                var!(conn)
                |> Plug.Conn.resp(unquote(status), unquote(name)(var!(conn)))
              end
            end
          else
            body = quote location: :keep do
              defp decide(unquote(name), var!(conn)) do
                var!(conn)
                |> Plug.Conn.resp(unquote(status), unquote(content))
              end
            end
          end

          {name, Map.put(bodies, name, body)}
        {:action, next} ->
          {next, bodies} = compile_decision(module, next, nodes, bodies)

          body = quote location: :keep do
            defp decide(unquote(name), var!(conn)) do
              decide(unquote(next), unquote(name)(var!(conn)))
            end
          end

          {name, Map.put(bodies, name, body)}
      end
    end
  end

  defmacro decision(name, consequent, alternate, args) do
    quote do
      @nodes Map.put(@nodes, unquote(name),
        {:decision, unquote(consequent), unquote(alternate), unquote(Macro.escape(args[:do], unquote: true)) })
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
end
