defmodule Decanter.DecisionGraph do
  require Decanter.DecisionGraph.Compiler, as: Compiler

  defmacro __using__(_) do
    quote location: :keep do
      import Decanter.DecisionGraph
      @before_compile Decanter.DecisionGraph

      @nodes %{}
      @decisions %{}
      @handlers %{}
      @dynamic HashSet.new

      defp handle_decision(ctx, result) do
        case result do
          {x, ctx} -> {x, ctx}
          x -> {x, ctx}
        end
      end
    end
  end

  defmacro __before_compile__(env) do
    defs = Enum.reduce(Module.definitions_in(env.module, :def), HashSet.new,
                        fn
                          ({name, 1}, set) -> Set.put(set, name)
                          (_, set) -> set
                        end)

    Compiler.compile(%{decisions: Module.get_attribute(env.module, :decisions),
                       defs: defs,
                       nodes: Module.get_attribute(env.module, :nodes),
                       dynamic: Module.get_attribute(env.module, :dynamic)},
                     %{entry_point: Module.get_attribute(env.module, :entry_point),
                       ctx_name: Module.get_attribute(env.module, :context_name)})
  end

  def generate_dot_file(nodes) do
    dot = for {name, node} <- nodes do
      case node do
        {:branch, test, consequent, alternate} ->
          """
            "#{to_string name}"->"#{to_string consequent}"[label="true"];
            "#{to_string name}"->"#{to_string alternate}"[label="false"];
            "#{to_string name}"[label="#{to_string test}"];
          """
        {:handler, status, _content} ->
          color = cond do
            status in 200..299 -> "0.25 0.48 1.0"
            status in 300..399 -> "0.61 0.48 1.0"
            status in 400..499 -> "0.1 0.72 1.0"
            status in 500..599 -> "1.0 0.7 0.8"
          end

          """
            "#{to_string name}" [
              label="#{to_string name}: #{to_string status}",
              style=filled,
              color="#{color}"
            ];
          """
        {:action, next} ->
          """
            "#{to_string name}"->"#{to_string next}";
            "#{to_string name}"[
              shape=circle,
              style=filled,
              color="0.33 0.58 0.86"
            ]
          """
      end
    end

    """
    digraph decisions {
      node[shape=box fontSize=12]
      edge[fontSize=12]
    #{Enum.join(dot, "")}
    }
    """
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

  defmacro dynamic(name) do
    quote do
      @dynamic Set.put(@dynamic, unquote(name))
    end
  end
end
