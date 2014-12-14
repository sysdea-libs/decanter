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

    {rewritten_entry_name, trees} = build_trees(env.module, entry_name, {counts, nodes}, %{})
    fn_bodies = compile_trees(trees)

    # IO.puts Macro.to_string(fn_bodies)

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

  defp build_trees(module, name, {counts, nodes}=cnodes, trees) do
    if trees[name] do
      {name, trees}
    else
      case nodes[name] do
        {:branch, test, consequent, alternate} ->
          case Module.get_attribute(module, :decisions)[test] do
            true -> build_trees(module, consequent, cnodes, trees)
            false -> build_trees(module, alternate, cnodes, trees)
            body ->
              {consequent, trees} = build_trees(module, consequent, cnodes, trees)
              {alternate, trees} = build_trees(module, alternate, cnodes, trees)
              same_path = consequent == alternate

              if counts[consequent] == 1 || (same_path && counts[consequent] == 2) do
                {:tree, consequent_body} = trees[consequent]
                trees = Map.delete(trees, consequent)
              else
                consequent_body = {:call, consequent}
              end

              if counts[alternate] == 1 do
                {:tree, alternate_body} = trees[alternate]
                trees = Map.delete(trees, alternate)
              else
                alternate_body = {:call, alternate}
              end

              # TODO: can this detection be cleaned up?
              # has_header is internal helper, check_setting is from tests
              strategy = case body do
                {:==, _, _} -> :if
                {:in, _, _} -> :if
                {:has_header, _, _} -> :if
                {:check_setting, _, _} -> :if
                _ -> :case
              end

              body = case {same_path, strategy} do
                {true, :if} ->
                  consequent_body
                {true, :case} ->
                  {:block, body, consequent_body}
                {false, :if} ->
                  {:if, body, consequent_body, alternate_body}
                {false, :case} ->
                  {:case_dec, body, consequent_body, alternate_body}
              end

              {name, Map.put(trees, name, {:tree, body})}
          end
        {:handler, status, content} ->
          handlers = Module.get_attribute(module, :handlers)

          body = if Map.has_key?(handlers, name) do
            {:handler, status, :case, Enum.reverse(handlers[name])}
          else
            {:handler, status, :string, content}
          end

          {name, Map.put(trees, name, {:tree, body})}
        {:action, next} ->
          {next, trees} = build_trees(module, next, cnodes, trees)
          {name, Map.put(trees, name, {:tree, {:action, name, next}})}
      end
    end
  end

  defp compile_trees(trees) do
    for tree <- trees do
      compile_tree(tree)
    end
  end

  defp compile_tree({name, {:tree, body}}) do
    quote location: :keep do
      defp do_decide(unquote(name), var!(conn)) do
        unquote(compile_node body)
      end
    end
  end

  defp compile_node({:call, name}) do
    quote do
      do_decide(unquote(name), var!(conn))
    end
  end
  defp compile_node({:block, body, consequent}) do
    quote location: :keep do
      {_, var!(conn)} = handle_decision(var!(conn), unquote(body))
      unquote(compile_node consequent)
    end
  end
  defp compile_node({:if, body, consequent, alternate}) do
    quote location: :keep do
      if unquote(body) do
        unquote(compile_node consequent)
      else
        unquote(compile_node alternate)
      end
    end
  end
  defp compile_node({:case_dec, body, consequent, alternate}) do
    quote location: :keep do
      case handle_decision(var!(conn), unquote(body)) do
        {true, var!(conn)} -> unquote(compile_node consequent)
        {false, var!(conn)} -> unquote(compile_node alternate)
      end
    end
  end
  defp compile_node({:handler, status, :case, handlers}) do
    handles = for {match,body} <- handlers do
      quote do
        unquote(match) -> unquote(body)
      end
    end

    quote do
      content = case var!(conn) do
        unquote(handles |> List.flatten)
      end

      Plug.Conn.resp(var!(conn), unquote(status), content)
    end
  end
  defp compile_node({:handler, status, :string, content}) do
    quote do
      Plug.Conn.resp(var!(conn), unquote(status), unquote(content))
    end
  end
  defp compile_node({:action, name, next}) do
    quote do
      do_decide(unquote(next), unquote(name)(var!(conn)))
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
