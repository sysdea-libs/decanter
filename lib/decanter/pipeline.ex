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
          case conn.resp_body do
            nil ->
              Plug.Conn.send_resp(conn, unquote(status), unquote(body))
            _ ->
              conn
              |> Plug.Conn.put_status(unquote(status))
              |> Plug.Conn.send_resp
          end
        end

        defoverridable [{name, 1}]
      end

      def call(conn, _opts) do
        conn = Plug.Conn.register_before_send conn, &Decanter.Pipeline.Utils.postprocess/1

        do_decant(:start, conn
                          |> Plug.Conn.assign(:headers, Enum.into(conn.req_headers, %{})))
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
  defmacro plug(name, opts \\ []) do
    quote do: Decanter.Pipeline.decanter_property(:plug, unquote(name), unquote(opts))
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
      body -> Plug.Conn.resp(conn, 200, body)
    end
  end
end
