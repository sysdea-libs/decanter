defmodule Decanter.DecisionGraph do
  require Decanter.DecisionGraph.Compiler, as: Compiler

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
    defs = Enum.reduce(Module.definitions_in(env.module, :def), HashSet.new,
                        fn
                          ({name, 1}, set) -> Set.put(set, name)
                          (_, set) -> set
                        end)

    entry_name = Module.get_attribute(env.module, :entry_point)
    Compiler.compile(%{decisions: Module.get_attribute(env.module, :decisions),
                       defs: defs,
                       nodes: Module.get_attribute(env.module, :nodes)}, entry_name)
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
end
