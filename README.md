# Wrangle

Port of [Liberator](http://clojure-liberator.github.io/liberator/) to Elixir, exposing as a Plug.

## Status

Primordial

## Why not just wrap cowboy_rest/webmachine?

Elixir can (theoretically) offer higher performance through macros, allowing it to inspect the defined Resource module and elide unused/defaulted decision points, such that the decision graph for each Resource is compiled from the definition. Cowboy_rest and webmachine are also both specific to their respective adapters, while Wrangle sits on top of Plug, so can support whichever adapters Plug supports.

## What about Phoenix?

Phoenix handles some of the format negotiation/body encoding issues, so the idea is that it will be possible to defer to Phoenix for formats/encoding, but still in Wrangle for when operating outside of Phoenix.

## Example

Port is still fairly direct, so the following is likely to improve:

```elixir
defmodule HelloResource do
  use Wrangle

  plug :serve

  def etag(_conn), do: 1635
  def last_modified(_conn), do: {{2014, 12, 13}, {11, 36, 32}}

  @available_media_types ["text/html", "application/json"]
  @allowed_methods ["POST", "GET"] # would be nice to auto-detect this

  handle :ok, %Plug.Conn{assigns: %{media_type: "text/html"}} do
    "<h1>HELLO</h1>"
  end

  handle :ok, %Plug.Conn{assigns: %{media_type: "application/json"}} do
    ~s({"message": "HELLO"})
  end

  def post!(conn) do
    # MyRepo.update(...)
  end
end
```
