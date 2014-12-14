# Wrangle

Port of [Liberator](http://clojure-liberator.github.io/liberator/) to Elixir, exposing as a Plug.

## Status

Experimental

## Why not just wrap cowboy_rest/webmachine?

`cowboy_rest` and `webmachine` are both specific to their respective adapters, while Wrangle sits on top of Plug, so can support whichever adapters Plug supports (which is currently only `cowboy`, but more are in the works).

Wrangle can also perhaps achieve higher performance as it uses macros to customise the compiled decision graph based on the resource definition. This allows the addition of extra decision points with no performance detriment, as boolean constant decisions are simply compiled away to nothing.

## What about Phoenix?

Phoenix handles some of the format negotiation/body encoding issues, so the idea is that it will be possible to defer to Phoenix for formats/encoding, but still in Wrangle for when operating outside of Phoenix.

## Example

Port is still fairly direct, so the following is likely to improve:

```elixir
defmodule HelloResource do
  use Wrangle

  plug :fetch_session
  plug :serve

  # static properties
  @available_media_types ["text/html", "application/json"]

  # dynamic properties
  def etag(_conn), do: 1635
  def last_modified(_conn), do: {{2014, 12, 13}, {11, 36, 32}}

  # decision points
  decide :authorized? do
    Map.has_key?(get_session(conn), :user)
  end

  # handlers
  handle :ok, %Plug.Conn{assigns: %{media_type: "text/html"}} do
    "<h1>HELLO</h1>"
  end

  handle :ok, %Plug.Conn{assigns: %{media_type: "application/json"}} do
    ~s({"message": "HELLO"})
  end

  # actions
  def post!(conn) do
    # MyRepo.update(...)
  end
end
```

## TODO

- [x] Inline unique decision paths.
- [x] Detect allowed_methods from action definitions?
- [ ] AOT analyse static properties rather than parsing on each request?
- [ ] Complete test suite.
- [ ] Documentation.
