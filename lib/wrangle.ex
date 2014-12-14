defmodule Wrangle do
  defmacro __using__(_) do
    quote location: :keep do
      @before_compile Wrangle

      use Wrangle.DecisionGraph
      import Wrangle.DecisionGraph
      import Wrangle
      require Wrangle.ConnectionNegotiator, as: ConNeg

      use Plug.Builder
      @behaviour Plug

      def init(opts) do
        opts
      end

      # util functions

      defp format_etag(etag) do
        case etag do
          nil -> nil
          etag -> "\"#{to_string(etag)}\""
        end
      end

      defp has_header(conn, header) do
        Map.has_key?(conn.assigns.headers, header)
      end

      # handlers

      handler :handle_ok, 200, "OK"
      handler :handle_options, 200, ""
      handler :handle_created, 201, ""
      handler :handle_accepted, 202, "Accepted."
      handler :handle_no_content, 204, ""

      handler :handle_multiple_representations, 300, ""
      handler :handle_see_other, 303, ""
      handler :handle_moved_permanently, 301, ""
      handler :handle_moved_temporarily, 307, ""
      handler :handle_not_modified, 304, ""

      handler :handle_malformed, 400, "Bad request."
      handler :handle_unauthorized, 401, "Not authorized."
      handler :handle_forbidden, 403, "Forbidden"
      handler :handle_method_not_allowed, 403, "Method not allowed."
      handler :handle_not_found, 404, "Resource not found."
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

      action :post!, :post_redirect?
      action :patch!, :respond_with_entity?
      action :put!, :new?
      action :delete!, :delete_enacted?
      action :options!, :handle_options

      # GET response annotations
      # TODO: This is wrong. Should put in the entry_point wrapper.
      # That will need some more careful compilation of the entry point to avoid
      # referencing functions that possibly don't exist (e
      decision :annotate_etag, :handle_ok, :handle_ok do
        if var!(conn).assigns[:etag] do
          true
        else
          etag = format_etag(etag var!(conn))
          {true, %{etag: etag}}
        end
      end
      branch :annotate_etag?, :supports_etag?, :annotate_etag, :handle_ok
      decision :annotate_last_modified, :annotate_etag?, :annotate_etag? do
        if var!(conn).assigns[:last_modified] do
          true
        else
          {true, %{last_modified: last_modified(var!(conn))}}
        end
      end
      branch :annotate_last_modified?, :supports_last_modified?,
                                       :annotate_last_modified, :annotate_etag?

      # decision graph

      decision :multiple_representations?, :handle_multiple_representations, :annotate_last_modified?
      decision :respond_with_entity?, :multiple_representations?, :handle_no_content
      decision :new?, :handle_created, :respond_with_entity?
      decision :post_redirect?, :handle_see_other, :new?
      decision :can_post_to_missing?, :post!, :handle_not_found
      branch :post_to_missing?, :method_post?, :can_post_to_missing?, :handle_not_found
      decision :can_post_to_gone?, :post!, :handle_gone
      branch :post_to_gone?, :method_post?, :can_post_to_gone?, :handle_not_found
      decision :moved_temporarily?, :handle_moved_temporarily, :post_to_gone?
      decision :moved_permanently?, :handle_moved_permanently, :moved_temporarily?
      decision :existed?, :moved_permanently?, :post_to_missing?
      decision :conflict?, :handle_conflict, :put!
      decision :can_put_to_missing?, :conflict?, :handle_not_implemented
      decision :put_to_different_url?, :handle_moved_permanently, :can_put_to_missing?
      decision :method_put?, :put_to_different_url?, :existed?
      decision :if_match_star_exists_for_missing?, :handle_precondition_failed, :method_put?
      decision :if_none_match?, :handle_not_modified, :handle_precondition_failed
      branch :put_to_existing?, :method_put?, :conflict?, :multiple_representations?
      branch :post_to_existing?, :method_post?, :post!, :put_to_existing?
      decision :delete_enacted?, :respond_with_entity?, :handle_accepted
      decision :method_patch?, :patch!, :post_to_existing?
      decision :method_delete?, :delete!, :method_patch?
      decision :modified_since?, :method_delete?, :handle_not_modified do
        case last_modified(var!(conn)) do
          nil -> true
          last_modified ->
            modsincedate = var!(conn).assigns[:if_modified_since_date]
            case last_modified == modsincedate do
              true -> false
              false -> {true, %{last_modified: last_modified}}
            end
        end
      end
      branch :last_modified_for_modified_since?, :supports_last_modified?,
                                                 :modified_since?, :method_delete?
      decision :if_modified_since_valid_date?, :last_modified_for_modified_since?, :method_delete? do
        datestring = to_char_list var!(conn).assigns.headers["if-modified-since"]
        case :httpd_util.convert_request_date(datestring) do
          :bad_date -> false
          date -> {true, %{if_modified_since_date: date}}
        end
      end
      decision :if_modified_since_exists?, :if_modified_since_valid_date?, :method_delete?
      decision :etag_matches_for_if_none?, :if_none_match?, :if_modified_since_exists? do
        etag = format_etag(etag var!(conn))
        {etag == var!(conn).assigns.headers["if-none-match"], %{etag: etag}}
      end
      branch :etag_for_if_none?, :supports_etag?,
                                 :etag_matches_for_if_none?, :if_modified_since_exists?
      decision :if_none_match_star?, :if_none_match?, :etag_for_if_none?
      decision :if_none_match_exists?, :if_none_match_star?, :if_modified_since_exists?
      decision :unmodified_since?, :handle_precondition_failed, :if_none_match_exists? do
        case last_modified(var!(conn)) do
          nil -> true
          last_modified ->
            unmodsincedate = var!(conn).assigns[:if_unmodified_since_date]
            case last_modified == unmodsincedate do
              true -> {false, %{last_modified: last_modified}}
              false -> true
            end
        end
      end
      branch :last_modified_for_since_exists?, :supports_last_modified?,
                                               :unmodified_since?, :handle_precondition_failed
      decision :if_unmodified_since_valid_date?, :last_modified_for_since_exists?, :if_none_match_exists? do
        datestring = to_char_list var!(conn).assigns.headers["if-unmodified-since"]
        case :httpd_util.convert_request_date(datestring) do
          :bad_date -> false
          date -> {true, %{if_unmodified_since_date: date}}
        end
      end
      decision :if_unmodified_since_exists?, :if_unmodified_since_valid_date?, :if_none_match_exists?
      decision :etag_matches_for_if_match?, :if_unmodified_since_exists?, :handle_precondition_failed do
        etag = format_etag(etag var!(conn))
        {etag == var!(conn).assigns.headers["if-match"], %{etag: etag}}
      end
      branch :etag_for_if_match?, :supports_etag?,
                                  :etag_matches_for_if_match?, :handle_precondition_failed
      decision :if_match_star?, :if_unmodified_since_exists?, :etag_for_if_match?
      decision :if_match_exists?, :if_match_star?, :if_unmodified_since_exists?
      decision :exists?, :if_match_exists?, :if_match_star_exists_for_missing?
      decision :processable?, :exists?, :handle_unprocessable_entity
      # TODO: not right treatment of identity when identity;q=0
      decision :encoding_available?, :processable?, :handle_not_acceptable do
        encoding = ConNeg.find_best(:encoding,
                                    var!(conn).assigns.headers["accept-encoding"],
                                    @available_encodings) || "identity"
        {true, %{encoding: encoding}}
      end
      decision :accept_encoding_exists?, :encoding_available?, :processable?
      decision :charset_available?, :accept_encoding_exists?, :handle_not_acceptable do
        charset = ConNeg.find_best(:charset, var!(conn).assigns.headers["accept-charset"], @available_charsets)
        {!is_nil(charset), %{charset: charset}}
      end
      decision :accept_charset_exists?, :charset_available?, :accept_encoding_exists?
      decision :language_available?, :accept_charset_exists?, :handle_not_acceptable do
        language = ConNeg.find_best(:language,
                                    var!(conn).assigns.headers["accept-language"],
                                    @available_languages)
        {!is_nil(language), %{language: language}}
      end
      decision :accept_language_exists?, :language_available?, :accept_charset_exists?
      decision :media_type_available?, :accept_language_exists?, :handle_not_acceptable do
        type = ConNeg.find_best(:accept, var!(conn).assigns.headers["accept"], @available_media_types)
        {!is_nil(type), %{media_type: type}}
      end
      decision :accept_exists?, :media_type_available?, :accept_language_exists? do
        if var!(conn).assigns.headers["accept"] do
          true
        else
          {false, %{media_type: ConNeg.find_best(:accept, "*/*", @available_media_types)}}
        end
      end
      decision :method_options?, :options!, :accept_exists?
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
      decide :delete_enacted?, do: true
      decide :existed?, do: false
      decide :exists?, do: true
      decide :known_content_type?, do: true
      decide :known_method?, do: var!(conn).method in @known_methods
      decide :malformed?, do: false
      decide :method_allowed?, do: var!(conn).method in @allowed_methods
      decide :moved_permanently?, do: false
      decide :moved_temporarily?, do: false
      decide :multiple_representations?, do: false
      decide :new?, do: true
      decide :post_redirect?, do: false
      decide :processable?, do: true
      decide :put_to_different_url?, do: false
      decide :respond_with_entity?, do: false
      decide :service_available?, do: true
      decide :uri_too_long?, do: false
      decide :valid_content_header?, do: true
      decide :valid_entity_length?, do: true

      # simple but only internally useful
      decide :accept_charset_exists?, do: has_header(var!(conn), "accept-charset")
      decide :accept_encoding_exists?, do: has_header(var!(conn), "accept-encoding")
      decide :accept_language_exists?, do: has_header(var!(conn), "accept-language")
      decide :if_match_exists?, do: has_header(var!(conn), "if-match")
      decide :if_match_star?, do: var!(conn).assigns.headers["if-match"] == "*"
      decide :if_match_star_exists_for_missing?, do: var!(conn).assigns.headers["if-match"] == "*"
      decide :if_modified_since_exists?, do: has_header(var!(conn), "if-modified-since")
      decide :if_none_match?, do: var!(conn).method in ["GET", "HEAD"]
      decide :if_none_match_exists?, do: has_header(var!(conn), "if-none-match")
      decide :if_none_match_star?, do: var!(conn).assigns.headers["if-none-match"] == "*"
      decide :if_unmodified_since_exists?, do: has_header(var!(conn), "if-unmodified-since")

      # Internal decision points that are automatically blanked when unsupported
      decide :method_delete?, do: var!(conn).method == "DELETE"
      decide :method_patch?, do: var!(conn).method == "PATCH"
      decide :method_put?, do: var!(conn).method == "PUT"
      decide :method_post?, do: var!(conn).method == "POST"
      decide :method_options?, do: var!(conn).method == "OPTIONS"

      # entry handler

      entry_point :service_available? do
        mapped_headers = Enum.into(var!(conn).req_headers, %{})

        # root specifies the actual root handler once ellision has taken place
        conn = do_decide(var!(root), %{
          var!(conn) | assigns: Map.merge(var!(conn).assigns, %{headers: mapped_headers})
        })

        if etag = conn.assigns[:etag] do
          conn = put_resp_header(conn, "ETag", etag)
        end

        if lm = conn.assigns[:last_modified] do
          conn = put_resp_header(conn, "Last-Modified", :httpd_util.rfc1123_date(lm) |> to_string)
        end

        if media_type = conn.assigns[:media_type] do
          if charset = conn.assigns[:charset] do
            conn = put_resp_header(conn, "Content-Type", "#{media_type};charset=#{charset}")
          else
            conn = put_resp_header(conn, "Content-Type", media_type)
          end
        end

        if language = conn.assigns[:language] do
          conn = put_resp_header(conn, "Content-Language", language)
        end

        if conn.assigns[:encoding] && conn.assigns[:encoding] != "identity" do
          conn = put_resp_header(conn, "Content-Encoding", conn.assigns[:encoding])
        end

        conn
      end

      # static properties

      @available_media_types ["text/html"]
      # @available_charsets ["utf-8"]
      # @available_encodings ["identity"]
      # @available_languages ["*"]
      # @allowed_methods ["POST", "GET"]
      @known_methods ["GET", "HEAD", "OPTIONS", "PUT", "POST", "DELETE", "TRACE", "PATCH"]
    end
  end

  defmacro __before_compile__(env) do
    quote do
      # Short circuit METHOD checks based on implemented action methods
      # Auto-generate an allowed_methods property if missing

      methods = ["GET"]

      if Module.defines?(__MODULE__, {:delete!, 1}) do
        methods = ["DELETE"|methods]
      else
        decide :method_delete?, do: false
      end

      if Module.defines?(__MODULE__, {:post!, 1}) do
        methods = ["POST"|methods]
      else
        decide :method_post?, do: false
      end

      if Module.defines?(__MODULE__, {:put!, 1}) do
        methods = ["PUT"|methods]
      else
        decide :method_put?, do: false
      end

      if Module.defines?(__MODULE__, {:patch!, 1}) do
        methods = ["PATCH"|methods]
      else
        decide :method_patch?, do: false
      end

      if Module.defines?(__MODULE__, {:options!, 1}) do
        methods = ["OPTIONS"|methods]
      else
        decide :method_options?, do: false
      end

      unless Module.get_attribute(__MODULE__, :allowed_methods) do
        @allowed_methods methods
      end


      # Short circuit ACCEPT checks based on implemented static properties
      unless Module.get_attribute(__MODULE__, :available_languages) do
        decide :accept_language_exists?, do: false
      end

      # Little more fuzzy on this one
      unless Module.get_attribute(__MODULE__, :available_charsets) do
        decide :accept_charset_exists?, do: false
      end

      unless Module.get_attribute(__MODULE__, :available_encodings) do
        decide :accept_encoding_exists?, do: false
      end

      # Add flags for deciding on etag/last_modified checks
      if Module.defines?(__MODULE__, {:etag, 1}) do
        decide :supports_etag?, do: true
      else
        decide :supports_etag?, do: false
      end

      if Module.defines?(__MODULE__, {:last_modified, 1}) do
        decide :supports_last_modified?, do: true
      else
        decide :supports_last_modified?, do: false
      end
    end
  end
end
