defmodule Decanter.DecisionGraph.Compiler do
  def compile(maps, options) do
    trees = build_trees(maps, options)

    # I'm pretty sure I'm making a hash of this line.
    compile_opts = %{ctx_name: quote(do: var!(unquote(Macro.var(options[:ctx_name], Elixir))))}

    Enum.map(trees, &compile_tree(&1, compile_opts))
  end

  defp build_trees(maps, options) do
    {_entry_name, trees} = do_build_trees(options[:entry_point], maps, %{}, options)
    trees
  end

  defp do_build_trees(name, %{nodes: nodes, decisions: decisions,
                              defs: defs}=maps, trees, options) do
    if trees[name] do
      {name, trees}
    else
      case nodes[name] do
        {:branch, test, consequent, alternate} ->
          case decisions[test] do
            true ->
              {inner_name, trees} = do_build_trees(consequent, maps, trees, options)
              {name, Map.put(trees, name, trees[inner_name])
                     |> Map.delete(inner_name)}
            false ->
              {inner_name, trees} = do_build_trees(alternate, maps, trees, options)
              {name, Map.put(trees, name, trees[inner_name])
                     |> Map.delete(inner_name)}
            handler when is_atom(handler) ->
              {inner_name, trees} = do_build_trees(handler, maps, trees, options)
              {name, Map.put(trees, name, trees[inner_name])
                     |> Map.delete(inner_name)}
            body ->
              {consequent, trees} = do_build_trees(consequent, maps, trees, options)
              {alternate, trees} = do_build_trees(alternate, maps, trees, options)
              consequent_body = {:call, consequent}
              alternate_body = {:call, alternate}

              same_path = consequent == alternate

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
          {next, trees} = do_build_trees(next, maps, trees, options)
          {name, Map.put(trees, name, {:tree, {:action, name, next}})}
      end
    end
  end

  def compile_tree({name, {:tree, body}}, options) do
    quote location: :keep do
      def do_decide(unquote(name), unquote(options.ctx_name)) do
        unquote(compile_node(body, options))
      end
    end
  end

  defp compile_node({:call, name}, options) do
    quote do
      do_decide(unquote(name), unquote(options.ctx_name))
    end
  end
  defp compile_node({:block, body, consequent}, options) do
    quote location: :keep do
      case handle_decision(unquote(options.ctx_name), unquote(body)) do
        {x, context} when is_atom(x) -> do_decide(x, context)
        {_, unquote(options.ctx_name)} -> unquote(compile_node(consequent, options))
      end
    end
  end
  defp compile_node({:if, body, consequent, alternate}, options) do
    quote location: :keep do
      if unquote(body) do
        unquote(compile_node(consequent, options))
      else
        unquote(compile_node(alternate, options))
      end
    end
  end
  defp compile_node({:case_dec, body, consequent, alternate}, options) do
    quote location: :keep do
      case handle_decision(unquote(options.ctx_name), unquote(body)) do
        {true, unquote(options.ctx_name)} -> unquote(compile_node(consequent, options))
        {false, unquote(options.ctx_name)} -> unquote(compile_node(alternate, options))
        {handler, context} -> do_decide(handler, context)
      end
    end
  end
  defp compile_node({:handler, status, :call, name}, options) do
    quote do
      unquote(name)(Plug.Conn.put_status(unquote(options.ctx_name), unquote(status)))
    end
  end
  defp compile_node({:handler, status, :string, content}, options) do
    quote do
      Plug.Conn.resp(unquote(options.ctx_name), unquote(status), unquote(content))
    end
  end
  defp compile_node({:action, name, next}, options) do
    quote do
      do_decide(unquote(next), unquote(name)(unquote(options.ctx_name)))
    end
  end
end
