# Decanter

Decanter is an experiment in exposing resources in Elixir using Plug. It currently contains two alternate approaches.

The first is a [Liberator](http://clojure-liberator.github.io/liberator/)/[webmachine](https://github.com/basho/webmachine)-style library in Elixir for exposing resources through a RESTful interface, on top of Plug. It's built on top of a dynamically built decision graph, allowing for ellision of fixed decisions, and customisation of the default HTTP decision graph. This allows it to be used on its own under Plug, or fit inside a larger framework such as Phoenix.

The second is a more Plug-like pipeline style approach that allows a clearer declaration of the flow of a request, at the expense of more easily allowing a badly behaving resource from the perspective of REST.

## Status

Highly Experimental. Has only been used internally with limited deployment, the API is still highly in flux.

# Liberator Style

## Example

```elixir
defmodule UserResource do
  use Decanter

  plug :fetch_session
  plug :serve

  # Stub collection
  @my_values %{"chris": "Chris Spencer",
               "ben": "Ben Smith"}

  # Resource properties
  # Could defer to Phoenix format/accepts handling
  def available_media_types(_conn), do: ["text/html", "application/json"]
  def etag(_conn), do: 1635
  def last_modified(_conn), do: {{2014, 12, 13}, {11, 36, 32}}

  # Decision points
  decide :allowed? do
    Map.has_key?(get_session(conn), :user)
  end

  # The `decide` macro inlines the tests and can optimise away constants.
  # Longer decisions can be defined normally to support pattern matching on the conn.
  def exists?(conn) do
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

# Actions, Handlers, Decisions and Properties

There's a [visualisation of the decision graph](https://cdn.rawgit.com/sysdea-libs/decanter/925b29a9e8394d3fe0b15ea7c4b160017f462880/graph/graph.svg) available in SVG form.

```elixir
# Static properties

@patch_content_types nil
@allowed_methods # autoset to ["OPTIONS", "GET"] + whichever actions are implemented
@known_methods ["GET", "HEAD", "OPTIONS", "PUT", "POST", "DELETE", "TRACE", "PATCH"]

# Dynamic properties, and their defaults when applicable

available_media_types(conn) # ["text/html"]
available_charsets(conn) # ["utf-8"]
available_encodings(conn) # ["identity"]
available_languages(conn) # ["*"]
etag(conn) # nil
last_modified(conn) # nil, should be an erlang style {date(),time()} or nil

# actions with their following decision point

post(conn) # => :new?
patch(conn) # => :respond_with_entity?
put(conn) # => :new?
delete(conn) # => :delete_enacted?

# handlers with their status code and default response

handle_ok(conn) # 200, "OK"
handle_options(conn) # 200, ""
handle_created(conn) # 201, ""
handle_accepted(conn) # 202, "Accepted."
handle_no_content(conn) # 204, ""

handle_multiple_representations(conn) # 300, ""
handle_moved_permanently(conn) # 301, ""
handle_see_other(conn) # 303, ""
handle_not_modified(conn) # 304, ""
handle_moved_temporarily(conn) # 307, ""

handle_malformed(conn) # 400, "Bad request."
handle_unauthorized(conn) # 401, "Not authorized."
handle_forbidden(conn) # 403, "Forbidden."
handle_not_found(conn) # 404, "Resource not found."
handle_method_not_allowed(conn) # 405, "Method not allowed."
handle_not_acceptable(conn) # 406, "No acceptable resource available."
handle_conflict(conn) # 409, "Conflict."
handle_gone(conn) # 410, "Resource is gone."
handle_precondition_failed(conn) # 412, "Precondition failed."
handle_request_entity_too_large(conn) # 413, "Request entity too large."
handle_uri_too_long(conn) # 414, "Request URI too long."
handle_unsupported_media_type(conn) # 415, "Unsupported media type."
handle_unprocessable_entity(conn) # 422, "Unprocessable entity."

handle_exception(conn) # 500, "Internal server error."
handle_not_implemented(conn) # 501, "Not implemented."
handle_unknown_method(conn) # 501, "Unknown method."
handle_service_not_available(conn) # 503, "Service not available."

# simple decision points, with default value
# there are more internal decision points that can be overriden when needed

:allowed?, do: true
:authorized?, do: true
:can_post_to_gone?, do: true
:can_post_to_missing?, do: true
:can_put_to_missing?, do: true
:conflict?, do: false
:create_enacted?, do: true
:delete_enacted?, do: true
:existed?, do: false
:exists?, do: true
:known_content_type?, do: true
:malformed?, do: false
:moved_permanently?, do: false
:moved_temporarily?, do: false
:multiple_representations?, do: false
:new?, do: true
:redirect_when_create_postponed?, do: false
:processable?, do: true
:put_to_different_url?, do: false
:respond_with_entity?, do: false
:service_available?, do: true
:uri_too_long?, do: false
:valid_content_header?, do: true
:valid_entity_length?, do: true
```

## Customising the decision graph

Sometimes you may not care about certain parts of the full HTTP decision graph, either because they are not applicable to your application, or because they are being handled by another library in the Plug chain. A common case for this would be when running inside Phoenix, where method and content negotation/checks are performed prior to routing to the Decanter plug.

### @entry_point

The easiest way to customise the graph is to simply start the decisions from further down the tree, using the `@entry_point` property. `:exists?` is a fairly suitable starting point in this context.

```elixir
defmodule MyPhoenixDecanter do
  use Decanter
  plug :serve

  @entry_point :exists?

  # ...
end
```

### Forwarding to another decision/handler

Sometimes the default positioning of certain checks may not make sense for your application. Consider pages that exist in multiple formats, but have special formats available only to the user that owns them. The `:allowed?` decision is where you can delegate to the appropriate `:handle_forbidden` by returning false, but happens before content negotiation and existence checking. In this case, it would make more sense for `:exists?` to be able to also declare a resource forbidden.

```elixir
defmodule MyUserDecanter do
  use Decanter
  plug :fetch_session
  plug :serve

  # Mark our media types
  def available_media_types(_), do: ["text/html", "application/json"]

  # We need to tell the graph builder that we are delegating to
  # :handle_forbidden dynamically, so it can ensure it's available.
  dynamic :handle_forbidden

  decide :exists? do
    user = get_session(conn, :user)
    file = Models.File.get(conn.params[:file_id])

    if is_nil(file) do
      false
    else if conn.assigns.media_type == "application/json" && file.owner.id != user.id do
      :handle_forbidden
    else
      {true, assign(conn, :file, file)}
    end
  end

  # ...
end
```

# Pipeline Style

## Example

```elixir
defmodule UserResource do
  use Decanter.Pipeline
  import Decanter.Pipeline

  # The decanter is called with :start for a new connection
  decanter :start do
    # Plugs, negotiations, and filters can be ordered to process a request
    plug :fetch_session
    negotiate media_type: ["text/html", "application/json"]
    filter :exists?
    filter :allowed?

    # etag/last_modified properties are checked after filters for caching/header population
    property :etag
    property :last_modified
    # the entity property is used when a representation is needed
    property :entity, fn: :show

    # Method declarations allow response behaviour configuration
    method :get
    method :put, send_entity: true
  end

  # Stub collection
  @my_values %{"chris": "Chris Spencer",
               "ben": "Ben Smith"}

  # Resource properties
  def etag(_conn), do: 1635
  def last_modified(_conn), do: {{2014, 12, 13}, {11, 36, 32}}

  # Decision points
  decide :allowed? do
    Map.has_key?(get_session(conn), :user)
  end

  # The `decide` macro inlines the tests and can optimise away constants.
  # Longer decisions can be defined normally to support pattern matching on the conn.
  def exists?(conn) do
    # Would defer to something like Plug.Router ordinarily
    ["user", id] = conn.path_info
    case @my_values[id] do
      nil -> false
      user -> {true, assign(conn, :user, user)}
    end
  end

  # Handlers
  def show(%{assigns: %{media_type: "text/html"}}=conn) do
    "<h1>#{conn.assigns.user}</h1>"
  end
  def show(%{assigns: %{media_type: "application/json"}}=conn) do
    ~s({"name": "#{conn.assigns.user}"})
  end

  # Actions
  def put(conn) do
    # MyRepo.update(@my_values ...)
  end
end
```

# License and Attribution

Released under the MIT License. Initial decision graph structure and content negotiation test cases attributed to [Liberator](http://clojure-liberator.github.io/liberator/).

# TODO

- [x] Inline unique decision paths.
- [x] Detect allowed_methods from action definitions
- [x] Options/Vary header construction
- [ ] Multi language accepts
- [ ] Complete test suite.
- [ ] Documentation.
