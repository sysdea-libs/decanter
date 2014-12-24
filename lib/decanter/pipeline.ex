defmodule Decanter.Pipeline.Builder do
  def compile(pipeline) do
    pipeline = Enum.reduce(pipeline, empty_pipeline, &build_pipeline(&1, &2))

    dispatcher = case pipeline do
      %{decant: decant} when not is_nil(decant) ->
        quote do
          do_decant(unquote(decant), var!(conn))
        end
      %{methods: methods} when map_size(methods) > 0 ->
        handlers = for {v, opts} <- methods do
          case {v, opts} do
            {m, fn: f} ->
              quote do
                unquote(verb m) -> unquote(f)(var!(conn))
              end
            {m, _} ->
              quote do
                unquote(verb m) -> unquote(m)(var!(conn))
              end
          end
        end ++ [quote do
                  _ -> handle_method_not_allowed(var!(conn))
                end]

        quote do
          case var!(conn).method do
            unquote(handlers |> List.flatten)
          end
        end
    end

    filter_chain = Enum.reduce Enum.reverse(pipeline.filters), dispatcher, &build_filter(&1, &2)

    IO.puts Macro.to_string(filter_chain)
    filter_chain
  end

  defp verb(:delete), do: "DELETE"
  defp verb(:patch), do: "PATCH"
  defp verb(:post), do: "POST"
  defp verb(:put), do: "PUT"
  defp verb(:get), do: "GET"

  @filters %{method_options?: {false, :handle_options},
             valid_entity_length?: {true, :handle_request_entity_too_large},
             known_content_type?: {true, :handle_unsupported_media_type},
             valid_content_header?: {true, :handle_not_implemented},
             allowed?: {true, :handle_forbidden},
             authorized?: {true, :handle_unauthorized},
             malformed?: {false, :handle_malformed},
             method_allowed?: {true, :handle_method_not_allowed},
             uri_too_long?: {false, :handle_uri_too_long},
             known_method?: {true, :handle_unknown_method},
             service_available?: {true, :handle_service_not_available},
             exists?: {true, :handle_not_found},
             multiple_representations?: {false, :handle_multiple_representations}}

  defp empty_pipeline do
    %{methods: %{}, properties: %{}, filters: [], decisions: %{}, decant: nil}
  end

  defp build_pipeline({:method, name, opts}, pipeline) do
    %{pipeline | methods: Map.put(pipeline.methods, name, opts)}
  end
  defp build_pipeline({:property, name, opts}, pipeline) do
    %{pipeline | properties: Map.put(pipeline.properties, name, opts)}
  end
  defp build_pipeline({:decide, name, opts}, pipeline) do
    %{pipeline | decisions: Map.put(pipeline.decisions, name, opts)}
  end
  defp build_pipeline({:filter, name, opts}, pipeline) do
    %{pipeline | filters: [{:filter, name, opts}|pipeline.filters]}
  end
  defp build_pipeline({:decant, body}, pipeline) do
    %{pipeline | decant: body}
  end
  defp build_pipeline({:negotiate, opts}, pipeline) do
    %{pipeline | filters: [{:negotiate, opts}|pipeline.filters]}
  end

  defp build_filter({:filter, name, opts}, acc) do
    f = opts[:fn] || name
    {branch, handler} = @filters[name]
    quote do
      case unquote(f)(var!(conn)) do
        {unquote(branch), var!(conn)} -> unquote(acc)
        {_, conn} -> unquote(handler)(conn)
      end
    end
  end

  defp build_filter({:negotiate, opts}, acc) do
    Enum.reduce opts, acc, &build_negotiate(&1, &2)
  end

  defp build_negotiate({:media_type, available}, acc) do
    quote do
      case ConNeg.negotiate(:media_type,
                            var!(conn).assigns.headers["accept"] || "*/*",
                            unquote(available)) do
        nil -> handle_not_acceptable(var!(conn)) # bail out
        media_type ->
          var!(conn) = assign(var!(conn), :media_type, media_type)
          unquote(acc)
      end
    end
  end
  defp build_negotiate({:charset, available}, acc) do
    quote do
      case ConNeg.negotiate(:charset,
                            var!(conn).assigns.headers["accept-charset"] || "*",
                            unquote(available)) do
        nil -> handle_not_acceptable(var!(conn)) # bail out
        charset ->
          var!(conn) = assign(var!(conn), :charset, charset)
          unquote(acc)
      end
    end
  end
end

defmodule Decanter.Pipeline do
  defmacro __using__(_) do
    quote do
      @before_compile Decanter.Pipeline
      import Decanter.Pipeline
      import Plug.Conn

      def handle_not_acceptable(conn) do end
      def handle_method_not_allowed(conn) do end
      def handle_forbidden(conn) do end
      def handle_not_found(conn) do end
    end
  end

  defmacro __before_compile__(env) do

  end

  defmacro decanter(match, do: block) do
    block =
      quote do
        @decanter_pipeline []
        unquote(block)
      end

    compiler =
      quote bind_quoted: [match: match] do
        body = Decanter.Pipeline.Builder.compile(@decanter_pipeline)
        defp do_decant(unquote(match), var!(conn)), do: unquote(body)
        @decanter_pipeline nil
      end

    [block, compiler]
  end

  defmacro negotiate(opts) do
    quote do
      @decanter_pipeline [{:negotiate, unquote(opts)}|@decanter_pipeline]
    end
  end

  defmacro decant(v) do
    quote do
      @decanter_pipeline [{:decant, unquote(Macro.escape(v))}|@decanter_pipeline]
    end
  end

  defmacro decanter_property(type, name, opts) do
    quote do
      @decanter_pipeline [{unquote(type), unquote(name), unquote(Macro.escape(opts))}|@decanter_pipeline]
    end
  end

  defmacro filter(name, opts \\ []) do
    quote do: decanter_property(:filter, unquote(name), unquote(opts))
  end
  defmacro decide(name, opts \\ []) do
    quote do: decanter_property(:decide, unquote(name), unquote(opts))
  end
  defmacro property(name, opts \\ []) do
    quote do: decanter_property(:property, unquote(name), unquote(opts))
  end
  defmacro method(name, opts \\ []) do
    quote do: decanter_property(:method, unquote(name), unquote(opts))
  end

  def send_resp(conn, resp) do
    Plug.Conn.send_resp(conn, conn.status, resp)
  end
end
