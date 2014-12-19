defmodule Decanter.DecisionGraph.Compiler do
  def compile(maps, options) do
    trees = build_trees(maps, options)

    # I'm pretty sure I'm making a hash of this line.
    compile_opts = %{
      ctx_name: quote do
        var!(unquote(Macro.var(options[:ctx_name], nil)))
      end
    }

    Enum.map(trees, &compile_tree(&1, compile_opts))
  end

  defp build_trees(maps, options) do
    {_entry_name, trees} = do_build_trees(options[:entry_point], maps, %{}, options)
    trees
  end

  defp do_build_trees(name, %{nodes: nodes, decisions: decisions,
                              defs: defs, dynamic: dynamic}=maps, trees, options) do
    if trees[name] do
      {name, trees}
    else
      case nodes[name] do
        {:branch, test, consequent, alternate} ->
          case {Set.member?(defs, test), decisions[test]} do
            {false, test_body} when is_boolean(test_body) or is_atom(test_body) ->
              inner = case test_body do
                true -> consequent
                false -> alternate
                handler -> handler
              end
              {inner_name, trees} = do_build_trees(inner, maps, trees, options)

              case Set.member?(dynamic, inner_name) do
                true -> {inner_name, trees}
                false -> {name, Map.put(trees, name, trees[inner_name])
                                |> Map.delete(inner_name)}
              end
            {has_fn, test_body} ->
              {consequent, trees} = do_build_trees(consequent, maps, trees, options)
              {alternate, trees} = do_build_trees(alternate, maps, trees, options)
              consequent_body = {:call, consequent}
              alternate_body = {:call, alternate}

              {test_body, strategy} = case {has_fn, test_body} do
                {true, _}        -> {{:dec_fn, test}, :case}
                {_, {:==, _, _}} -> {{:inline, test_body}, :if}
                {_, {:in, _, _}} -> {{:inline, test_body}, :if}
                _                -> {{:inline, test_body}, :case}
              end

              body = case {consequent == alternate, strategy} do
                {true, :if}    -> consequent_body
                {true, :case}  -> {:block, test_body, consequent_body}
                {false, :if}   -> {:if, test_body, consequent_body, alternate_body}
                {false, :case} -> {:case_dec, test_body, consequent_body, alternate_body}
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
  defp compile_node({:dec_fn, test}, options) do
    quote location: :keep do
      unquote(test)(unquote(options.ctx_name))
    end
  end
  defp compile_node({:inline, body}, options) do
    body
  end
  defp compile_node({:block, test, consequent}, options) do
    quote location: :keep do
      case handle_decision(unquote(options.ctx_name), unquote(compile_node(test, options))) do
        {:return, context} -> context
        {x, context} when is_atom(x) -> do_decide(x, context)
        {_, unquote(options.ctx_name)} -> unquote(compile_node(consequent, options))
      end
    end
  end
  defp compile_node({:if, test, consequent, alternate}, options) do
    quote location: :keep do
      if unquote(compile_node(test, options)) do
        unquote(compile_node(consequent, options))
      else
        unquote(compile_node(alternate, options))
      end
    end
  end
  defp compile_node({:case_dec, test, consequent, alternate}, options) do
    quote location: :keep do
      case handle_decision(unquote(options.ctx_name), unquote(compile_node(test, options))) do
        {:return, context} -> context
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
      Plug.Conn.send_resp(unquote(options.ctx_name), unquote(status), unquote(content))
    end
  end
  defp compile_node({:action, name, next}, options) do
    quote do
      do_decide(unquote(next), unquote(name)(unquote(options.ctx_name)))
    end
  end
end
