defmodule Divulger do
  import Divulger.Builder
  require Divulger.ConnectionNegotiator, as: ConNeg

  defmacro __using__(_) do
    quote location: :keep do
      use Plug.Builder
      @behaviour Plug

      def init(opts) do
        opts
      end

      def serve(conn, opts) do
        mapped_headers = Enum.into(conn.req_headers, %{})
        decide(:service_available?, %{
          conn | assigns: Map.merge(conn.assigns, %{headers: mapped_headers})
        })
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


      decision :multiple_representations?, :handle_multiple_representations, :handle_ok
      decision :respond_with_entity?, :multiple_representations?, :handle_no_content
      decision :new?, :handle_created, :respond_with_entity?
      decision :post_redirect?, :handle_see_other, :new?

      decision :can_post_to_missing?, :post!, :handle_not_found
      decision :post_to_missing?, &(&1.method == "POST"), :can_post_to_missing?, :handle_not_found
      decision :can_post_to_gone?, :post!, :handle_gone

      decision :post_to_gone?, &(&1.method == "POST"), :can_post_to_gone?, :handle_not_found

      decision :moved_temporarily?, :handle_moved_temporarily, :post_to_gone?
      decision :moved_permanently?, :handle_moved_permanently, :moved_temporarily?
      decision :existed?, :moved_permanently, :post_to_missing?

      decision :conflict?, :handle_conflict, :put!

      decision :can_put_to_missing?, :conflict?, :handle_not_implemented
      decision :put_to_different_url?, :handle_moved_permanently, :can_put_to_missing?

      decision :method_put?, &(&1.method == "PUT"), :put_to_different_url?, :existed?

      decision :if_match_star_exists_for_missing?, &(&1.assigns.headers["if-match"] == "*"),
                                                   :handle_precondition_failed, :method_put?

      decision :if_none_match?, &(&1.method in ["GET", "HEAD"]),
                                :handle_not_modified, :handle_precondition_failed
      decision :put_to_existing?, &(&1.method == "PUT"),
                                  :conflict?, :multiple_representations?
      decision :post_to_existing?, &(&1.method == "POST"),
                                   :post!, :put_to_existing?

      decision :delete_enacted?, :respond_with_entity?, :handle_accepted

      decision :method_patch?, &(&1.method == "PATCH"), :patch!, :post_to_existing?
      decision :method_delete?, &(&1.method == "DELETE"), :delete!, :method_patch?

      defp gen_last_modified(conn) do
        case last_modified(conn) do
          nil -> nil
          lm -> lm
        end
      end

      defp gen_etag(conn) do
        case etag(conn) do
          false -> nil
          etag -> "\"#{to_string(etag)}\""
        end
      end

      defp do_modified_since(conn) do
        case gen_last_modified(conn) do
          nil -> true
          last_modified ->
            lmdate = Timex.Date.from(last_modified)
            case Timex.Date.diff(conn.assigns[:if_modified_since_date], lmdate, :secs) do
              0 -> false
              _ -> {true, %{last_modified: lmdate}}
            end
        end
      end

      decision :modified_since?, :do_modified_since, :method_delete?, :handle_not_modified

      defp do_if_modified_since_valid_date(conn) do
        case Timex.DateFormat.parse(conn.assigns.headers["if-modified-since"], "{RFC1123}") do
          {:ok, date} -> {true, %{if_modified_since_date: date}}
          _ -> false
        end
      end

      decision :if_modified_since_valid_date?, :do_if_modified_since_valid_date,
                                               :modified_since?, :method_delete?

      decision :if_modified_since_exists?, &(Map.has_key? &1.assigns.headers, "if-modified-since"),
                                           :if_modified_since_valid_date?, :method_delete?

      defp do_etag_matches_for_if_none(conn) do
        etag = gen_etag(conn)
        {etag == conn.assigns.headers["if-none-match"], %{etag: etag}}
      end

      decision :etag_matches_for_if_none?, :do_etag_matches_for_if_none,
                                           :if_none_match?, :if_modified_since_exists?

      decision :if_none_match_star?, &(&1.assigns.headers["if-none-match"] == "*"),
                                     :if_none_match?, :etag_matches_for_if_none?

      decision :if_none_match_exists?, &(Map.has_key? &1.assigns.headers, "if-none-match"),
                                       :if_none_match_star?, :if_modified_since_exists?

      defp do_unmodified_since(conn) do
        case gen_last_modified(conn) do
          nil -> true
          last_modified ->
            lmdate = Timex.Date.from(last_modified)
            case Timex.Date.diff(conn.assigns[:if_unmodified_since_date], lmdate, :secs) do
              0 -> {false, %{last_modified: lmdate}}
              _ -> true
            end
        end
      end

      decision :unmodified_since?, :do_unmodified_since,
                                   :handle_precondition_failed, :if_none_match_exists

      defp do_if_unmodified_since_valid_date(conn) do
        case Timex.DateFormat.parse(conn.assigns.headers["if-unmodified-since"], "{RFC1123}") do
          {:ok, date} -> {true, %{if_unmodified_since_date: date}}
          _ -> false
        end
      end

      decision :if_unmodified_since_valid_date?, :do_if_unmodified_since_valid_date,
                                                 :unmodified_since?, :if_none_match_exists?

      decision :if_unmodified_since_exists?, &(Map.has_key? &1.assigns.headers, "if-unmodified-since"),
                                             :if_unmodified_since_valid_date?, :if_none_match_exists?

      defp do_etag_matches_for_if_match(conn) do
        etag = gen_etag(conn)
        {etag == conn.assigns.headers["if-match"], %{etag: etag}}
      end

      decision :etag_matches_for_if_match?, :do_etag_matches_for_if_match,
                                            :if_unmodified_since_exists?, :handle_precondition_failed

      decision :if_match_star?, &(&1.assigns.headers["if-match"] == "*"),
                                :if_unmodified_since_exists?, :etag_matches_for_if_match?

      decision :if_match_exists?, &(Map.has_key? &1.assigns.headers, "if-match"),
                                  :if_match_star?, :if_unmodified_since_exists?

      decision :exists?, :if_match_exists?, :if_match_star_exists_for_missing?

      decision :processable?, :exists?, :handle_unprocessable_entity

      # TODO: not right treatment of identity when identity;q=0
      defp do_encoding_available(conn) do
        encoding = ConNeg.find_best(:encoding,
                                    conn.assigns.headers["accept-encoding"],
                                    available_encodings) || "identity"
        {true, %{encoding: encoding}}
      end

      decision :encoding_available?, :do_encoding_available,
                                     :processable?, :handle_not_acceptable

      decision :accept_encoding_exists?, &(Map.has_key? &1.assigns.headers, "accept-encoding"),
                                         :encoding_available?, :processable?

      defp do_charset_available(conn) do
        charset = ConNeg.find_best(:charset, conn.assigns.headers["accept-charset"], available_charsets)
        {!is_nil(charset), %{charset: charset}}
      end

      decision :charset_available?, :do_charset_available,
                                    :accept_encoding_exists?, :handle_not_acceptable

      decision :accept_charset_exists?, &(Map.has_key? &1.assigns.headers, "accept-charset"),
                                        :charset_available?, :accept_encoding_exists?

      defp do_language_available(conn) do
        language = ConNeg.find_best(:language,
                                    conn.assigns.headers["accept-language"],
                                    available_languages)
        {!is_nil(language), %{language: language}}
      end

      decision :language_available?, :do_language_available,
                                     :accept_charset_exists?, :handle_not_acceptable

      decision :accept_language_exists?, &(Map.has_key? &1.assigns.headers, "accept-language"),
                                         :language_available?, :accept_charset_exists?

      defp do_negotiate_media_type(conn) do
        type = ConNeg.find_best(:accept, conn.assigns.headers["accept"], available_media_types)
        {!is_nil(type), %{media_type: type}}
      end

      decision :media_type_available?, :do_negotiate_media_type,
                                       :accept_language_exists?, :handle_not_acceptable

      defp do_accept_exists(conn) do
        if conn.assigns.headers["accept"] do
          true
        else
          {false, %{media_type: ConNeg.find_best(:accept, "*/*", available_media_types)}}
        end
      end

      decision :accept_exists?, :do_accept_exists,
                                :media_type_available?, :accept_language_exists?

      decision :is_options?, &(&1.method == "OPTIONS"), :handle_options, :accept_exists?
      decision :valid_entity_length?, :is_options?, :handle_request_entity_too_large
      decision :known_content_type?, :valid_entity_length?, :handle_unsupported_media_type
      decision :valid_content_header?, :known_content_type?, :handle_not_implemented
      decision :allowed?, :valid_content_header?, :handle_forbidden
      decision :authorized?, :allowed?, :handle_unauthorized
      decision :malformed?, :handle_malformed, :authorized?
      decision :method_allowed?, :malformed?, :handle_method_not_allowed
      decision :uri_too_long?, :handle_uri_too_long, :method_allowed?
      decision :known_method?, :uri_too_long?, :handle_unknown_method
      decision :service_available?, :known_method?, :handle_service_not_available

      action :post!, :post_redirect?
      action :patch!, :respond_with_entity?
      action :put!, :new?
      action :delete!, :delete_enacted?

      # default implementations
      default_bool :service_available?, true

      def known_methods, do: ["GET", "HEAD", "OPTIONS", "PUT", "POST", "DELETE", "TRACE", "PATCH"]
      def known_method?(conn), do: conn.method in known_methods

      default_bool :uri_too_long?, false

      def allowed_methods, do: ["POST", "GET"]
      defp method_allowed?(conn), do: conn.method in allowed_methods

      default_bool :malformed?,                false
      default_bool :authorized?,               true
      default_bool :allowed?,                  true
      default_bool :valid_content_header?,     true
      default_bool :known_content_type?,       true
      default_bool :valid_entity_length?,      true
      default_bool :exists?,                   true
      default_bool :existed?,                  false
      default_bool :respond_with_entity?,      false
      default_bool :new?,                      true
      default_bool :post_redirect?,            false
      default_bool :put_to_different_url?,     false
      default_bool :multiple_representations?, false
      default_bool :conflict?,                 false
      default_bool :can_post_to_missing?,      true
      default_bool :can_put_to_missing?,       true
      default_bool :can_post_to_gone?,         false
      default_bool :moved_permanently?,        false
      default_bool :moved_temporarily?,        false
      default_bool :delete_enacted?,           true
      default_bool :processable?,              true

      def available_media_types, do: ["text/html"]
      def available_charsets, do: ["utf-8"]
      def available_encodings, do: ["identity"]
      def available_languages, do: ["*"]

      def last_modified(_conn), do: nil

      def etag(_), do: false

      defoverridable [allowed_methods: 0,
                      method_allowed?: 1,
                      known_methods: 0,
                      known_method?: 1,
                      last_modified: 1,
                      etag: 1,
                      available_media_types: 0,
                      available_charsets: 0,
                      available_encodings: 0]
    end
  end
end
