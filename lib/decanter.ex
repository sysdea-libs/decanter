defmodule Decanter do
  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Decanter

      use Decanter.DecisionGraph
      use Plug.Builder
      require Decanter.ConnectionNegotiator, as: ConNeg
      import Decanter

      def init(opts) do
        opts
      end

      defoverridable [init: 1]

      # Configure context naming for decision graph

      @context_name :conn

      # handlers

      handler :handle_ok, 200, "OK"
      handler :handle_options, 200, ""
      handler :handle_created, 201, ""
      handler :handle_accepted, 202, "Accepted."
      handler :handle_no_content, 204, ""

      handler :handle_multiple_representations, 300, ""
      handler :handle_moved_permanently, 301, ""
      handler :handle_see_other, 303, ""
      handler :handle_not_modified, 304, ""
      handler :handle_moved_temporarily, 307, ""

      handler :handle_malformed, 400, "Bad request."
      handler :handle_unauthorized, 401, "Not authorized."
      handler :handle_forbidden, 403, "Forbidden."
      handler :handle_not_found, 404, "Resource not found."
      handler :handle_method_not_allowed, 405, "Method not allowed."
      handler :handle_not_acceptable, 406, "No acceptable resource available."
      handler :handle_conflict, 409, "Conflict."
      handler :handle_gone, 410, "Resource is gone."
      handler :handle_precondition_failed, 412, "Precondition failed."
      handler :handle_request_entity_too_large, 413, "Request entity too large."
      handler :handle_uri_too_long, 414, "Request URI too long."
      handler :handle_unsupported_media_type, 415, "Unsupported media type."
      handler :handle_unprocessable_entity, 422, "Unprocessable entity."

      handler :handle_exception, 500, "Internal server error."
      handler :handle_not_implemented, 501, "Not implemented."
      handler :handle_unknown_method, 501, "Unknown method."
      handler :handle_service_not_available, 503, "Service not available."

      # actions

      action :post, :new_post?
      action :patch, :respond_with_entity?
      action :put, :new_put?
      action :delete, :delete_enacted?

      # decision graph

      decision :multiple_representations?, :handle_multiple_representations, :handle_ok
      decision :respond_with_entity?, :multiple_representations?, :handle_no_content
      decision :redirect_on_create?, :handle_see_other, :handle_created
      branch :create_enacted_put?, :create_enacted?, :handle_created, :handle_accepted
      branch :new_put?, :new?, :create_enacted_put?, :respond_with_entity?
      branch :create_enacted_post?, :create_enacted?, :redirect_on_create?, :handle_accepted
      branch :new_post?, :new?, :create_enacted_post?, :respond_with_entity?
      decision :can_post_to_missing?, :post, :handle_not_found
      branch :post_to_missing?, :method_post?, :can_post_to_missing?, :handle_not_found
      decision :can_post_to_gone?, :post, :handle_gone
      branch :post_to_gone?, :method_post?, :can_post_to_gone?, :handle_not_found
      decision :moved_temporarily?, :handle_moved_temporarily, :post_to_gone?
      decision :moved_permanently?, :handle_moved_permanently, :moved_temporarily?
      decision :existed?, :moved_permanently?, :post_to_missing?
      decision :conflict?, :handle_conflict, :put
      decision :can_put_to_missing?, :conflict?, :handle_not_implemented
      decision :put_to_different_url?, :handle_moved_permanently, :can_put_to_missing?
      decision :method_put?, :put_to_different_url?, :existed?
      decision :if_match_star_exists_for_missing?, :handle_precondition_failed, :method_put?
      decision :method_get_or_head?, :handle_not_modified, :handle_precondition_failed
      branch :put_to_existing?, :method_put?, :conflict?, :multiple_representations?
      branch :post_to_existing?, :method_post?, :post, :put_to_existing?
      decision :delete_enacted?, :respond_with_entity?, :handle_accepted
      decision :method_patch?, :patch, :post_to_existing?
      decision :method_delete?, :delete, :method_patch?
      decision :modified_since?, :method_delete?, :handle_not_modified do
        modified_date = var!(conn).assigns[:if_modified_since_date]
        case last_modified(var!(conn)) do
          nil -> true
          ^modified_date -> false
          last_modified -> {true, assign(var!(conn), :last_modified, last_modified)}
        end
      end
      decision :if_modified_since_valid_date?, :modified_since?, :method_delete? do
        datestring = to_char_list var!(conn).assigns.headers["if-modified-since"]
        case :httpd_util.convert_request_date(datestring) do
          :bad_date -> false
          date -> {true, assign(var!(conn), :if_modified_since_date, date)}
        end
      end
      decision :if_modified_since_exists?, :if_modified_since_valid_date?, :method_delete?
      branch :last_modified_for_modified_since_exists?, :supports_last_modified?,
                                                        :if_modified_since_exists?, :method_delete?
      decision :etag_matches_for_if_none?, :method_get_or_head?, :last_modified_for_modified_since_exists? do
        etag = format_etag(etag var!(conn))
        {etag == var!(conn).assigns.headers["if-none-match"], assign(var!(conn), :etag, etag)}
      end
      branch :etag_for_if_none?, :supports_etag?,
                                 :etag_matches_for_if_none?, :last_modified_for_modified_since_exists?
      decision :if_none_match_star?, :method_get_or_head?, :etag_for_if_none?
      decision :if_none_match_exists?, :if_none_match_star?, :last_modified_for_modified_since_exists?
      decision :unmodified_since?, :if_none_match_exists?, :handle_precondition_failed do
        unmodified_date = var!(conn).assigns[:if_unmodified_since_date]
        case last_modified(var!(conn)) do
          ^unmodified_date -> {true, assign(var!(conn), :last_modified, unmodified_date)}
          _ -> false
        end
      end
      branch :last_modified_for_since_exists?, :supports_last_modified?,
                                               :unmodified_since?, :handle_precondition_failed
      decision :if_unmodified_since_valid_date?, :last_modified_for_since_exists?, :if_none_match_exists? do
        datestring = to_char_list var!(conn).assigns.headers["if-unmodified-since"]
        case :httpd_util.convert_request_date(datestring) do
          :bad_date -> false
          date -> {true, assign(var!(conn), :if_unmodified_since_date, date)}
        end
      end
      decision :if_unmodified_since_exists?, :if_unmodified_since_valid_date?, :if_none_match_exists?
      decision :etag_matches_for_if_match?, :if_unmodified_since_exists?, :handle_precondition_failed do
        etag = format_etag(etag var!(conn))
        {etag == var!(conn).assigns.headers["if-match"], assign(var!(conn), :etag, etag)}
      end
      branch :etag_for_if_match?, :supports_etag?,
                                  :etag_matches_for_if_match?, :handle_precondition_failed
      decision :if_match_star?, :if_unmodified_since_exists?, :etag_for_if_match?
      decision :if_match_exists?, :if_match_star?, :if_unmodified_since_exists?
      decision :exists?, :if_match_exists?, :if_match_star_exists_for_missing?
      decision :processable?, :exists?, :handle_unprocessable_entity
      decision :encoding_available?, :processable?, :handle_not_acceptable do
        encoding = ConNeg.find_best(:encoding,
                                    var!(conn).assigns.headers["accept-encoding"],
                                    @available_encodings)
        {true, assign(var!(conn), :encoding, encoding)}
      end
      decision :accept_encoding_exists?, :encoding_available?, :processable?
      decision :charset_available?, :accept_encoding_exists?, :handle_not_acceptable do
        charset = ConNeg.find_best(:charset, var!(conn).assigns.headers["accept-charset"], @available_charsets)
        {!is_nil(charset), assign(var!(conn), :charset, charset)}
      end
      decision :accept_charset_exists?, :charset_available?, :accept_encoding_exists?
      decision :language_available?, :accept_charset_exists?, :handle_not_acceptable do
        language = ConNeg.find_best(:language,
                                    var!(conn).assigns.headers["accept-language"],
                                    @available_languages)
        {!is_nil(language), assign(var!(conn), :language, language)}
      end
      decision :accept_language_exists?, :language_available?, :accept_charset_exists?
      decision :media_type_available?, :accept_language_exists?, :handle_not_acceptable do
        case ConNeg.find_best(:accept, var!(conn).assigns.headers["accept"], @available_media_types) do
          nil -> false
          media_type -> {true, assign(var!(conn), :media_type, media_type)}
        end
      end
      decision :accept_exists?, :media_type_available?, :accept_language_exists? do
        if has_header(var!(conn), "accept") do
          true
        else
          case ConNeg.find_best(:accept, "*/*", @available_media_types) do
            nil -> :handle_not_acceptable # bail out
            media_type -> {false, assign(var!(conn), :media_type, media_type)}
          end
        end
      end
      decision :method_options?, :handle_options, :accept_exists?
      decision :valid_entity_length?, :method_options?, :handle_request_entity_too_large
      decision :known_content_type?, :valid_entity_length?, :handle_unsupported_media_type
      decision :valid_content_header?, :known_content_type?, :handle_not_implemented
      decision :allowed?, :valid_content_header?, :handle_forbidden
      decision :authorized?, :allowed?, :handle_unauthorized
      decision :malformed?, :handle_malformed, :authorized?
      decision :method_allowed?, :malformed?, :handle_method_not_allowed
      decision :uri_too_long?, :handle_uri_too_long, :method_allowed?
      decision :known_method?, :uri_too_long?, :handle_unknown_method
      decision :service_available?, :known_method?, :handle_service_not_available

      # default simple decisions
      decide :allowed?, do: true
      decide :authorized?, do: true
      decide :can_post_to_gone?, do: true
      decide :can_post_to_missing?, do: true
      decide :can_put_to_missing?, do: true
      decide :conflict?, do: false
      decide :create_enacted?, do: true
      decide :delete_enacted?, do: true
      decide :existed?, do: false
      decide :exists?, do: true
      decide :known_content_type?, do: true
      decide :malformed?, do: false
      decide :moved_permanently?, do: false
      decide :moved_temporarily?, do: false
      decide :multiple_representations?, do: false
      decide :new?, do: true
      decide :redirect_on_create?, do: false
      decide :processable?, do: true
      decide :put_to_different_url?, do: false
      decide :respond_with_entity?, do: false
      decide :service_available?, do: true
      decide :uri_too_long?, do: false
      decide :valid_content_header?, do: true
      decide :valid_entity_length?, do: true

      # simple but only internally useful
      decide :known_method?, do: var!(conn).method in @known_methods
      decide :method_allowed?, do: var!(conn).method in @allowed_methods
      decide :accept_charset_exists?, do: has_header(var!(conn), "accept-charset")
      decide :accept_encoding_exists?, do: has_header(var!(conn), "accept-encoding")
      decide :accept_language_exists?, do: has_header(var!(conn), "accept-language")
      decide :if_match_exists?, do: has_header(var!(conn), "if-match")
      decide :if_match_star?, do: var!(conn).assigns.headers["if-match"] == "*"
      decide :if_match_star_exists_for_missing?, do: var!(conn).assigns.headers["if-match"] == "*"
      decide :if_modified_since_exists?, do: has_header(var!(conn), "if-modified-since")
      decide :if_none_match_exists?, do: has_header(var!(conn), "if-none-match")
      decide :if_none_match_star?, do: var!(conn).assigns.headers["if-none-match"] == "*"
      decide :if_unmodified_since_exists?, do: has_header(var!(conn), "if-unmodified-since")
      decide :method_get_or_head?, do: var!(conn).method in ["GET", "HEAD"]

      # Internal decision points that are automatically blanked when unsupported
      decide :method_delete?, do: var!(conn).method == "DELETE"
      decide :method_patch?, do: var!(conn).method == "PATCH"
      decide :method_put?, do: var!(conn).method == "PUT"
      decide :method_post?, do: var!(conn).method == "POST"
      decide :method_options?, do: var!(conn).method == "OPTIONS"

      # entry handler

      @entry_point :service_available?

      # static properties

      @patch_content_types nil
      @available_media_types ["text/html"]
      @available_charsets ["utf-8"]
      @available_encodings ["identity"]
      @available_languages ["*"]
      # @allowed_methods ["POST", "GET"]
      @known_methods ["GET", "HEAD", "OPTIONS", "PUT", "POST", "DELETE", "TRACE", "PATCH"]
    end
  end

  # util functions

  def format_etag(etag) do
    case etag do
      nil -> nil
      etag -> "\"#{to_string(etag)}\""
    end
  end

  def has_header(conn, header) do
    Map.has_key?(conn.assigns.headers, header)
  end

  def put_resp(conn, resp) do
    Plug.Conn.resp(conn, conn.status, resp)
  end

  defmacro __before_compile__(env) do
    # Short circuit METHOD checks based on implemented action methods
    {methods, decisions} =
      Enum.reduce [{"DELETE", :delete, :method_delete?},
                   {"POST", :post, :method_post?},
                   {"PUT", :put, :method_put?},
                   {"PATCH", :patch, :method_patch?}],
                  {["GET", "OPTIONS"], []},
                  fn ({method, name, decision}, {methods, decisions}) ->
      if Module.defines?(env.module, {name, 1}) do
        {[method|methods], decisions}
      else
        form = quote do
          decide unquote(decision), do: false
        end
        {methods, [form|decisions]}
      end
    end

    supports_etag = Module.defines?(env.module, {:etag, 1})
    supports_last_modified = Module.defines?(env.module, {:last_modified, 1})

    etag_check = if supports_etag do
      quote do
        if etag = var!(conn).assigns[:etag] || format_etag(etag var!(conn)) do
          var!(conn) = put_resp_header(var!(conn), "ETag", etag)
        else
          var!(conn)
        end
      end
    else
      quote do var!(conn) end
    end

    last_modified_check = if supports_last_modified do
      quote do
        if last_modified = var!(conn).assigns[:last_modified] || last_modified(var!(conn)) do
          put_resp_header(var!(conn), "Last-Modified",
                          :httpd_util.rfc1123_date(last_modified) |> to_string)
        else
          var!(conn)
        end
      end
    else
      quote do var!(conn) end
    end

    quote do
      # Auto-insert an allowed_methods property if missing
      unless Module.get_attribute(__MODULE__, :allowed_methods) do
        @allowed_methods unquote(Macro.escape methods)
      end

      # Override method decisions
      unquote(decisions)

      # Add flags for deciding on etag/last_modified checks
      decide :supports_etag?, do: unquote(supports_etag)
      decide :supports_last_modified?, do: unquote(supports_last_modified)

      # Generate entry point
      def serve(var!(conn), opts) do
        mapped_headers = Enum.into(var!(conn).req_headers, %{})

        # root specifies the actual root handler once ellision has taken place
        var!(conn) = do_decide(@entry_point, var!(conn)
                                             |> assign(:headers, mapped_headers)
                                             |> assign(:opts, opts))

        conn = unquote(etag_check)
        conn = unquote(last_modified_check)

        if conn.method == "OPTIONS" or conn.status == 405 do
          conn = put_resp_header(conn, "Allow", Enum.join(@allowed_methods, ","))
          if @patch_content_types do
            conn = put_resp_header(conn, "Accept-Patch", Enum.join(@patch_content_types, ","))
          end
        end

        {vary, conn} = case conn.assigns do
          %{media_type: media_type, charset: charset} ->
            {["Accept-Charset", "Accept"],
             put_resp_header(conn, "Content-Type", "#{media_type};charset=#{charset}")}
          %{media_type: media_type} ->
            {["Accept"],
             put_resp_header(conn, "Content-Type", media_type)}
          _ -> {[], conn}
        end

        if language = conn.assigns[:language] do
          vary = ["Accept-Language"|vary]
          conn = put_resp_header(conn, "Content-Language", language)
        end

        if conn.assigns[:encoding] && conn.assigns[:encoding] != "identity" do
          vary = ["Accept-Encoding"|vary]
          conn = put_resp_header(conn, "Content-Encoding", conn.assigns[:encoding])
        end

        unless Enum.empty?(vary) do
          conn = put_resp_header(conn, "Vary", Enum.join(vary, ","))
        end

        conn
      end
    end
  end
end
