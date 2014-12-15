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

  decide exists? do
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
  def put!(conn) do
    # MyRepo.update(@my_values ...)
  end
end
```

## Why not just wrap cowboy_rest/webmachine?

`cowboy_rest` and `webmachine` are both specific to their respective adapters, while Decanter sits on top of Plug, so can support whichever adapters Plug supports (which is currently only `cowboy`, but more are in the works).

## What about Phoenix?

Phoenix handles some of the format negotiation/body encoding issues, so the idea is that it will be possible to defer to Phoenix for formats/encoding, but still in Decanter for when operating outside of Phoenix.

## TODO

- [x] Inline unique decision paths.
- [x] Detect allowed_methods from action definitions?
- [ ] AOT analyse static properties rather than parsing on each request?
- [x] Options/Vary header construction
- [ ] Complete test suite.
- [ ] Documentation.
