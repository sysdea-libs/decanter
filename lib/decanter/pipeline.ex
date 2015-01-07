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
          build_verb(v, pipeline.properties, opts)
        end ++ [quote do
                  _ -> handle_method_not_allowed(var!(conn))
                end]

        d = quote do
          case var!(conn).method do
            unquote(handlers |> List.flatten)
          end
        end

        build_cache_check(pipeline.properties, d)
    end

    filter_chain = Enum.reduce Enum.reverse(pipeline.filters), dispatcher, &build_filter(&1, &2)

    IO.puts Macro.to_string(filter_chain)
    filter_chain
  end

  defp build_verb(:get, props, _opts) do
    entity = build_accessor(:entity, props[:entity])

    quote do
      "GET" -> handle_ok(Decanter.Pipeline.wrap_entity(var!(conn), unquote(entity)))
    end
  end
  defp build_verb(:delete, props, opts) do
    delete = build_accessor(:delete, opts)

    quote do
      "DELETE" -> handle_no_content(unquote(delete))
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
    case Keyword.get(opts, :entity_body, true) do
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
      case Decanter.Pipeline.cache_check(var!(conn), var!(conn).assigns.headers, unquote(last_modified), unquote(etag)) do
        {:ok, var!(conn)} -> unquote(acc)
        {:precondition, conn} -> handle_precondition_failed(conn)
        {:not_modified, conn} -> handle_not_modified(conn)
      end
    end
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

  @handlers [{:handle_ok, 200, "OK"},
             {:handle_options, 200, ""},
             {:handle_created, 201, ""},
             {:handle_accepted, 202, "Accepted."},
             {:handle_no_content, 204, ""},

             {:handle_multiple_representations, 300, ""},
             {:handle_moved_permanently, 301, ""},
             {:handle_see_other, 303, ""},
             {:handle_not_modified, 304, ""},
             {:handle_moved_temporarily, 307, ""},

             {:handle_malformed, 400, "Bad request."},
             {:handle_unauthorized, 401, "Not authorized."},
             {:handle_forbidden, 403, "Forbidden."},
             {:handle_not_found, 404, "Resource not found."},
             {:handle_method_not_allowed, 405, "Method not allowed."},
             {:handle_not_acceptable, 406, "No acceptable resource available."},
             {:handle_conflict, 409, "Conflict."},
             {:handle_gone, 410, "Resource is gone."},
             {:handle_precondition_failed, 412, "Precondition failed."},
             {:handle_request_entity_too_large, 413, "Request entity too large."},
             {:handle_uri_too_long, 414, "Request URI too long."},
             {:handle_unsupported_media_type, 415, "Unsupported media type."},
             {:handle_unprocessable_entity, 422, "Unprocessable entity."},

             {:handle_exception, 500, "Internal server error."},
             {:handle_not_implemented, 501, "Not implemented."},
             {:handle_unknown_method, 501, "Unknown method."},
             {:handle_service_not_available, 503, "Service not available."}]

  defmacro __using__(_) do

    handlers = Macro.escape @handlers

    quote bind_quoted: binding do
      for {name, status, body} <- handlers do
        def unquote(name)(conn) do
          if conn.resp_body do
            conn
            |> Plug.Conn.put_status(unquote(status))
            |> Plug.Conn.send_resp
          else
            Plug.Conn.send_resp(conn, unquote(status), unquote(body))
          end
        end

        defoverridable [{name, 1}]
      end
    end
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
    quote do: Decanter.Pipeline.decanter_property(:filter, unquote(name), unquote(opts))
  end
  defmacro property(name, opts \\ []) do
    quote do: Decanter.Pipeline.decanter_property(:property, unquote(name), unquote(opts))
  end
  defmacro method(name, opts \\ []) do
    quote do: Decanter.Pipeline.decanter_property(:method, unquote(name), unquote(opts))
  end

  # Utility/connection checks

  def cache_check(conn, headers, last_modified, etag) do
    conn = conn
           |> Plug.Conn.assign(conn, :etag, etag)
           |> Plug.Conn.assign(conn, :last_modified, last_modified)

    status = case cache_check_ifmatch(headers, etag) do
      :ok ->
        case cache_check_ifnonematch(conn.method, headers, etag) do
          :ok ->
            case cache_check_ifunmodified(headers, last_modified) do
              :ok ->
                cache_check_ifmodified(headers, last_modified)
              status -> status
            end
          status -> status
        end
      status -> status
    end

    {status, conn}
  end

  def cache_check_ifmatch(headers, etag) do
    case headers["if-match"] do
      nil -> :ok
      "*" -> :ok
      ^etag -> :ok
      _ -> :precondition
    end
  end

  def cache_check_ifnonematch(method, headers, etag) do
    case headers["if-none-match"] do
      nil -> :ok
      i_n_m when i_n_m == "*" or i_n_m == etag ->
        if method in ["GET", "HEAD"] do
          :not_modified
        else
          :precondition
        end
      _ ->
        :ok
    end
  end

  def cache_check_ifunmodified(headers, last_modified) do
    case headers["if-unmodified-since"] do
      nil -> :ok
      ds ->
        case :httpd_util.convert_request_date(ds |> to_char_list) do
          :bad_date -> :ok
          ^last_modified -> :ok
          _ -> :precondition
        end
    end
  end

  def cache_check_ifmodified(headers, last_modified) do
    case headers["if-modified-since"] do
      nil -> :ok
      ds ->
        case :httpd_util.convert_request_date(ds |> to_char_list) do
          :bad_date -> :ok
          ^last_modified -> :not_modified
          _ -> :ok
        end
    end
  end

  # Helper wrappers

  def filter_wrap(ctx, result) do
    case result do
      {x, ctx} -> {x, ctx}
      x -> {x, ctx}
    end
  end

  def wrap_entity(conn, entity) do
    case entity do
      %Plug.Conn{} -> entity
      body -> Plug.Conn.resp(conn, conn.status, body)
    end
  end
end
