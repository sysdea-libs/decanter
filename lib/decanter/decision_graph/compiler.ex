defmodule Decanter.DecisionGraph.Compiler do
  def compile(maps, name) do
    {^name, trees} = maps
                     |> add_counts(name)
                     |> build_trees(name)

    Enum.map(trees, &compile_tree(&1))
  end

  defp add_counts(maps, name) do
    initial_counts = for x <- maps.dynamic, do: {x, 1}, into: %{}
    base_counts = Map.put(maps, :counts, do_visit_nodes(name, maps, initial_counts))
  end

  defp do_visit_nodes(name, %{nodes: nodes, decisions: decisions}=maps, acc) do
    if acc[name] do
      Map.put(acc, name, acc[name] + 1)
    else
      case nodes[name] do
        {:branch, test, consequent, alternate} ->
          case decisions[test] do
            true -> do_visit_nodes(consequent, maps, acc)
            false -> do_visit_nodes(alternate, maps, acc)
            _body ->
              acc = do_visit_nodes(consequent, maps, acc)
              acc = do_visit_nodes(alternate, maps, acc)
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
          acc = do_visit_nodes(next, maps, acc)
          if acc[name] do
            Map.put(acc, name, acc[name] + 1)
          else
            Map.put(acc, name, 1)
          end
      end
    end
  end

  defp build_trees(maps, name) do
    do_build_trees(name, maps, %{})
  end

  defp do_build_trees(name, %{nodes: nodes, decisions: decisions,
                              defs: defs, counts: counts}=maps, trees) do
    if trees[name] do
      {name, trees}
    else
      case nodes[name] do
        {:branch, test, consequent, alternate} ->
          case decisions[test] do
            true ->
              {inner_name, trees} = do_build_trees(consequent, maps, trees)
              {name, Map.put(trees, name, trees[inner_name])
                     |> Map.delete(inner_name)}
            false ->
              {inner_name, trees} = do_build_trees(alternate, maps, trees)
              {name, Map.put(trees, name, trees[inner_name])
                     |> Map.delete(inner_name)}
            handler when is_atom(handler) ->
              {inner_name, trees} = do_build_trees(handler, maps, trees)
              {name, Map.put(trees, name, trees[inner_name])
                     |> Map.delete(inner_name)}
            body ->
              {consequent, trees} = do_build_trees(consequent, maps, trees)
              {alternate, trees} = do_build_trees(alternate, maps, trees)
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

              strategy = case body do
                {:==, _, _} -> :if
                {:in, _, _} -> :if
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
          body = if Set.member?(defs, name) do
            {:handler, status, :call, name}
          else
            {:handler, status, :string, content}
          end

          {name, Map.put(trees, name, {:tree, body})}
        {:action, next} ->
          {next, trees} = do_build_trees(next, maps, trees)
          {name, Map.put(trees, name, {:tree, {:action, name, next}})}
      end
    end
  end

  def compile_tree({name, {:tree, body}}) do
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
      case handle_decision(var!(conn), unquote(body)) do
        {x, conn} when is_atom(x) -> do_decide(x, conn)
        {_, var!(conn)} -> unquote(compile_node consequent)
      end
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
        {handler, conn} -> do_decide(handler, conn)
      end
    end
  end
  defp compile_node({:handler, status, :call, name}) do
    quote do
      unquote(name)(Plug.Conn.put_status(var!(conn), unquote(status)))
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
end
