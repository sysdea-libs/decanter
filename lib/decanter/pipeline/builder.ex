defmodule Decanter.Pipeline.Builder do
  def compile(pipeline) do
    pipeline = Enum.reduce(pipeline, empty_pipeline, &build_pipeline(&1, &2))

    dispatcher = case pipeline do
      %{decant: decant} when not is_nil(decant) ->
        quote do
          do_decant(unquote(decant), var!(conn))
        end
      %{methods: methods} when map_size(methods) > 0 ->
        verbs = Map.put(methods, :options, nil)
                |> Enum.map(&verb_name(elem(&1, 0)))
                |> Enum.join(",")

        handlers = for {v, opts} <- methods do
          build_verb(v, pipeline.properties, opts)
        end ++ [quote do
                  "OPTIONS" -> handle_options(Plug.Conn.put_resp_header(var!(conn), "Allow", unquote(verbs)))
                  _ -> handle_method_not_allowed(Plug.Conn.put_resp_header(var!(conn), "Allow", unquote(verbs)))
                end]

        d = quote do
          case var!(conn).method do
            unquote(handlers |> List.flatten)
          end
        end

        build_cache_check(pipeline.properties, d)
    end

    filter_chain = Enum.reduce Enum.reverse(pipeline.filters), dispatcher, &build_filter(&1, &2)

    # IO.puts Macro.to_string(filter_chain)
    filter_chain
  end

  defp verb_name(:get), do: "GET"
  defp verb_name(:post), do: "POST"
  defp verb_name(:patch), do: "PATCH"
  defp verb_name(:put), do: "PUT"
  defp verb_name(:delete), do: "DELETE"
  defp verb_name(:options), do: "OPTIONS"

  defp build_verb(:get, props, _opts) do
    entity = build_accessor(:entity, props[:entity])

    quote do
      "GET" ->
        var!(conn)
        |> Decanter.Pipeline.wrap_entity(unquote(entity))
        |> handle_ok
    end
  end
  defp build_verb(:delete, _props, opts) do
    delete = build_accessor(:delete, opts)

    quote do
      "DELETE" ->
        case unquote(delete) do
          %Plug.Conn{halted: true}=conn -> conn
          conn -> handle_no_content(conn)
        end
    end
  end
  defp build_verb(:patch, props, opts) do
    patch = build_accessor(:patch, opts)
    entity = build_accessor(:entity, props[:entity])
    responder = build_responder(opts, entity)

    quote do
      "PATCH" -> unquote(build_action patch, responder)
    end
  end
  defp build_verb(:post, props, opts) do
    post = build_accessor(:post, opts)
    entity = build_accessor(:entity, props[:entity], post)
    responder = build_responder(opts, entity)

    quote do
      "POST" -> unquote(build_action post, responder)
    end
  end
  defp build_verb(:put, props, opts) do
    put = build_accessor(:put, opts)
    entity = build_accessor(:entity, props[:entity], put)
    responder = build_responder(opts, entity)

    quote do
      "PUT" -> unquote(build_action put, responder)
    end
  end

  defp build_accessor(name, opts, acc \\ quote do: var!(conn)) do
    case opts[:fn] do
      nil -> quote do: unquote(name)(unquote(acc))
      f -> quote do: unquote(f)(unquote(acc))
    end
  end

  defp build_action(action, responder) do
    quote do
      case unquote(action) do
        %Plug.Conn{halted: true}=conn -> conn
        var!(conn) -> unquote(responder)
      end
    end
  end

  defp build_responder(opts, entity) do
    case Keyword.get(opts, :send_entity, true) do
      true ->
        quote do: handle_ok(Decanter.Pipeline.wrap_entity(var!(conn), unquote(entity)))
      false ->
        quote do: handle_no_content(var!(conn))
      test ->
        quote do
          if unquote(test) do
            handle_ok(Decanter.Pipeline.wrap_entity(var!(conn), unquote(entity)))
          else
            handle_no_content(var!(conn))
          end
        end
    end
  end

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
             gone?: {true, :handle_gone},
             multiple_representations?: {false, :handle_multiple_representations}}

  defp empty_pipeline do
    %{methods: %{}, properties: %{}, filters: [], decant: nil}
  end

  defp build_pipeline({:method, name, opts}, pipeline) do
    %{pipeline | methods: Map.put(pipeline.methods, name, opts)}
  end
  defp build_pipeline({:property, name, opts}, pipeline) do
    %{pipeline | properties: Map.put(pipeline.properties, name, opts)}
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
  defp build_pipeline({:plug, name, opts}, pipeline) do
    %{pipeline | filters: [{:plug, name, opts}|pipeline.filters]}
  end

  defp build_filter({:filter, name, opts}, acc) do
    f = opts[:fn] || name
    {branch, handler} = @filters[name]
    quote do
      case Decanter.Pipeline.filter_wrap(var!(conn), unquote(f)(var!(conn))) do
        {unquote(branch), var!(conn)} -> unquote(acc)
        {_, conn} -> unquote(handler)(conn)
      end
    end
  end
  defp build_filter({:negotiate, opts}, acc) do
    Enum.reduce opts, acc, &build_negotiate(&1, &2)
  end
  defp build_filter({:plug, name, opts}, acc) do
    quote_plug(init_plug({name, opts}), acc)
  end

  # Copied from Plug.Builder

  defp init_plug({plug, opts}) do
    case Atom.to_char_list(plug) do
      'Elixir.' ++ _ ->
        init_module_plug(plug, opts)
      _ ->
        init_fun_plug(plug, opts)
    end
  end

  defp init_module_plug(plug, opts) do
    opts = plug.init(opts)

    if function_exported?(plug, :call, 2) do
      {:call, plug, opts}
    else
      raise ArgumentError, message: "#{inspect plug} plug must implement call/2"
    end
  end

  defp init_fun_plug(plug, opts) do
    {:fun, plug, opts}
  end

  defp quote_plug({:call, plug, opts}, acc) do
    call = quote do: unquote(plug).call(var!(conn), unquote(Macro.escape(opts)))

    quote do
      case unquote(call) do
        %Plug.Conn{halted: true} = conn -> conn
        %Plug.Conn{} = var!(conn)       -> unquote(acc)
        _ -> raise "expected #{unquote(inspect plug)}.call/2 to return a Plug.Conn"
      end
    end
  end

  defp quote_plug({:fun, plug, opts}, acc) do
    call = quote do: unquote(plug)(var!(conn), unquote(Macro.escape(opts)))

    quote do
      case unquote(call) do
        %Plug.Conn{halted: true} = conn -> conn
        %Plug.Conn{} = var!(conn)       -> unquote(acc)
        _ -> raise "expected #{unquote(plug)}/2 to return a Plug.Conn"
      end
    end
  end

  # End Copy

  defp build_cache_check(props, acc) do
    last_modified = case props[:last_modified] do
      nil -> nil
      last_mod -> build_accessor(:last_modified, last_mod)
    end

    etag = case props[:etag] do
      nil -> nil
      etag -> build_accessor(:etag, etag)
    end

    quote do
      case Decanter.Pipeline.Utils.cache_check(var!(conn), var!(conn).assigns.headers, unquote(last_modified), unquote(etag)) do
        {:ok, var!(conn)} -> unquote(acc)
        {:precondition, conn} -> handle_precondition_failed(conn)
        {:not_modified, conn} -> handle_not_modified(conn)
      end
    end
  end

  defp build_negotiate({type, available}, acc) do
    quote do
      case Decanter.Pipeline.Utils.negotiate(unquote(type), var!(conn), unquote(available)) do
        {:ok, var!(conn)} -> unquote(acc)
        {:not_acceptable, conn} -> handle_not_acceptable(conn)
      end
    end
  end
end