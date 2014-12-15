# Decanter

Port of [Liberator](http://clojure-liberator.github.io/liberator/) to Elixir, as a Plug. Exposes resources through a RESTful interface.

## Status

Highly Experimental. Has not yet been used outside of basic testing, the API is still highly in flux.

## Example

```elixir
defmodule UserResource do
  use Decanter

  plug :fetch_session
  plug :serve

  # Stub collection
  @my_values %{"chris": "Chris Spencer",
               "ben": "Ben Smith"}

  # Static properties
  # Could defer to Phoenix format/accepts handling
  @available_media_types ["text/html", "application/json"]

  # Dynamic properties
  def etag(_conn), do: 1635
  def last_modified(_conn), do: {{2014, 12, 13}, {11, 36, 32}}

  # Decision points
  decide :allowed? do
    Map.has_key?(get_session(conn), :user)
  end

  decide :exists? do
    # Would defer to something like Plug.Router ordinarily
    ["user", id] = conn.path_info
    case @my_values[id] do
      nil -> false
      user -> {true, assign(conn, :user, user)}
    end
  end

  # Return a representation after post/put/patch
  decide :respond_with_entity?, do: true
  # Only allow put to an existing key
  decide :can_put_to_missing?, do: false

  # Handlers
  def handle_ok(%{assigns: %{media_type: "text/html"}}=conn) do
    put_resp(conn, "<h1>#{conn.assigns.user}</h1>")
  end

  def handle_ok(%{assigns: %{media_type: "application/json"}}=conn) do
    put_resp(conn, ~s({"name": "#{conn.assigns.user}"}))
  end

  # Actions
  def put(conn) do
    # MyRepo.update(@my_values ...)
  end
end
```

## Why not just wrap cowboy_rest/webmachine?

`cowboy_rest` and `webmachine` are both specific to their respective adapters, while Decanter sits on top of Plug, so can support whichever adapters Plug supports (which is currently only `cowboy`, but more are in the works).

## What about Phoenix?

Phoenix handles some of the format negotiation/body encoding issues, so the idea is that it will be possible to defer to Phoenix for formats/encoding, but still in Decanter for when operating outside of Phoenix.

# Actions, Handlers and Decisions

```elixir
# actions with their following decision point

:post, :post_redirect?
:patch, :respond_with_entity?
:put, :new?
:delete, :delete_enacted?

# handlers with their status code and default response

:handle_ok, 200, "OK"
:handle_options, 200, ""
:handle_created, 201, ""
:handle_accepted, 202, "Accepted."
:handle_no_content, 204, ""

:handle_multiple_representations, 300, ""
:handle_moved_permanently, 301, ""
:handle_see_other, 303, ""
:handle_not_modified, 304, ""
:handle_moved_temporarily, 307, ""

:handle_malformed, 400, "Bad request."
:handle_unauthorized, 401, "Not authorized."
:handle_forbidden, 403, "Forbidden."
:handle_not_found, 404, "Resource not found."
:handle_method_not_allowed, 405, "Method not allowed."
:handle_not_acceptable, 406, "No acceptable resource available."
:handle_conflict, 409, "Conflict."
:handle_gone, 410, "Resource is gone."
:handle_precondition_failed, 412, "Precondition failed."
:handle_request_entity_too_large, 413, "Request entity too large."
:handle_uri_too_long, 414, "Request URI too long."
:handle_unsupported_media_type, 415, "Unsupported media type."
:handle_unprocessable_entity, 422, "Unprocessable entity."

:handle_exception, 500, "Internal server error."
:handle_not_implemented, 501, "Not implemented."
:handle_unknown_method, 501, "Unknown method."
:handle_service_not_available, 503, "Service not available."

# simple decision points, with default value
# there are more internal decision points that can be overriden when needed

:allowed?, do: true
:authorized?, do: true
:can_post_to_gone?, do: true
:can_post_to_missing?, do: true
:can_put_to_missing?, do: true
:conflict?, do: false
:delete_enacted?, do: true
:existed?, do: false
:exists?, do: true
:known_content_type?, do: true
:malformed?, do: false
:moved_permanently?, do: false
:moved_temporarily?, do: false
:multiple_representations?, do: false
:new?, do: true
:post_redirect?, do: false
:processable?, do: true
:put_to_different_url?, do: false
:respond_with_entity?, do: false
:service_available?, do: true
:uri_too_long?, do: false
:valid_content_header?, do: true
:valid_entity_length?, do: true
```

## TODO

- [x] Inline unique decision paths.
- [x] Detect allowed_methods from action definitions?
- [ ] AOT analyse static properties rather than parsing on each request?
- [x] Options/Vary header construction
- [ ] Complete test suite.
- [ ] Documentation.
