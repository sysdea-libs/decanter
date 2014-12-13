# Divulger

Port of [Liberator](http://clojure-liberator.github.io/liberator/) to Elixir, exposing as a Plug.

## Status

Primordial

## Why not just wrap cowboy_rest/webmachine?

Elixir can (theoretically) offer higher performance through macros, allowing it to inspect the defined Resource module and elide unused/defaulted decision points, such that the decision graph for each Resource is compiled from the definition. Cowboy_rest and webmachine are also both specific to their respective adapters, while Divulger sits on top of Plug, so can support whichever adapters Plug supports.

## What about Phoenix?

Phoenix handles some of the format negotiation/body encoding issues, so the idea is that it will be possible to defer to Phoenix for formats/encoding, but still in Divulger for when operating outside of Phoenix.

## Example

Rudimentary example, as the port is currently very direct, and not yet adapted to be more Elixir-like in use.

```elixir
defmodule HelloResource do
  use Divulger

  plug :serve

  def etag(_conn), do: 1635
  def last_modified(_conn), do: {{2014, 12, 13}, {11, 36, 32}}

  def available_media_types, do: ["text/html", "application/json"]

  def handle_ok(%Plug.Conn{assigns: %{media_type: "text/html"}}) do
    "<h1>HELLO</h1>"
  end

  def handle_ok(%Plug.Conn{assigns: %{media_type: "application/json"}}) do
    ~s({"message": "HELLO"})
  end
end
```

A possible adaptation would be:

```elixir
defmodule HelloResource do
  use Divulger

  plug :serve

  @media_types ["text/html", "application/json"]

  def etag(_conn), do: 1635
  def last_modified(_conn), do: {{2014, 12, 13}, {11, 36, 32}}

  def handle(:ok, _conn, %{media_type: "text/html"}) do
    "<h1>HELLO</h1>"
  end

  def handle(:ok, _conn, %{media_type: "application/json"}) do
    ~s({"message": "HELLO"})
  end
end
```
