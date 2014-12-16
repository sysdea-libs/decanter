defmodule Decanter.DecisionGraph.Compiler do
  def compile(maps, entry_point, ctx_name) do
    {^entry_point, trees} = maps
                     |> add_counts(entry_point)
                     |> build_trees(entry_point)

    # I'm pretty sure I'm making a hash of this line.
    ctx = %{ctx_name: quote(do: var!(unquote(Macro.var(ctx_name, Elixir))))}

    Enum.map(trees, &compile_tree(ctx, &1))
  end

  defp add_counts(maps, name) do
    dynamic_counts = for x <- maps.dynamic, do: {x, 1}, into: %{}
    Map.put(maps, :counts, Map.merge(do_visit_nodes(name, maps, %{}),
                                     dynamic_counts,
                                     fn _, a, b -> a + b end))
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
            handler when is_atom(handler) ->
              do_visit_nodes(handler, maps, acc)
              |> Map.put(name, 1)
            _body ->
              acc = do_visit_nodes(consequent, maps, acc)
              do_visit_nodes(alternate, maps, acc)
              |> Map.put(name, 1)
          end
        {:handler, _status, _content} ->
          Map.put(acc, name, 1)
        {:action, next} ->
          do_visit_nodes(next, maps, acc)
          |> Map.put(name, 1)
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

  def compile_tree(ctx, {name, {:tree, body}}) do
    quote location: :keep do
      defp do_decide(unquote(name), unquote(ctx.ctx_name)) do
        unquote(compile_node(ctx, body))
      end
    end
  end

  defp compile_node(ctx, {:call, name}) do
    quote do
      do_decide(unquote(name), unquote(ctx.ctx_name))
    end
  end
  defp compile_node(ctx, {:block, body, consequent}) do
    quote location: :keep do
      case handle_decision(unquote(ctx.ctx_name), unquote(body)) do
        {x, context} when is_atom(x) -> do_decide(x, context)
        {_, unquote(ctx.ctx_name)} -> unquote(compile_node(ctx, consequent))
      end
    end
  end
  defp compile_node(ctx, {:if, body, consequent, alternate}) do
    quote location: :keep do
      if unquote(body) do
        unquote(compile_node(ctx, consequent))
      else
        unquote(compile_node(ctx, alternate))
      end
    end
  end
  defp compile_node(ctx, {:case_dec, body, consequent, alternate}) do
    quote location: :keep do
      case handle_decision(unquote(ctx.ctx_name), unquote(body)) do
        {true, unquote(ctx.ctx_name)} -> unquote(compile_node(ctx, consequent))
        {false, unquote(ctx.ctx_name)} -> unquote(compile_node(ctx, alternate))
        {handler, context} -> do_decide(handler, context)
      end
    end
  end
  defp compile_node(ctx, {:handler, status, :call, name}) do
    quote do
      unquote(name)(Plug.Conn.put_status(unquote(ctx.ctx_name), unquote(status)))
    end
  end
  defp compile_node(ctx, {:handler, status, :string, content}) do
    quote do
      Plug.Conn.resp(unquote(ctx.ctx_name), unquote(status), unquote(content))
    end
  end
  defp compile_node(ctx, {:action, name, next}) do
    quote do
      do_decide(unquote(next), unquote(name)(unquote(ctx.ctx_name)))
    end
  end
end
