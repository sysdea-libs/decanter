# json is authenticated, handles PATCH/GET/DELETE
# PATCH/GET/DELETE should 404 if not present
# PATCH should return a the new entity
# DELETE should 204
# should support caching via last modified date

# html version is unauthenticated
# embeds a representation of the user if logged in
# should not be cacheable

defmodule Decanter.PipelineTest do
  use Decanter.Pipeline
  import Decanter.Pipeline
  import Plug.Conn

  plug :decant

  decanter :start do
    negotiate media_type: ["text/html", "application/json"],
                 charset: ["utf-8"]
    decant conn.assigns.media_type
  end

  decanter "text/html" do
    property :entity, fn: :as_html

    method :get
  end

  decanter "application/json" do
    filter :exists?
    filter :allowed?, fn: :user_has_access?

    property :last_modified
    property :entity, fn: :as_json

    method :get
    method :patch
    method :delete
  end

  # Access/existence checks

  def exists?(%{params: %{"model_id" => model_id}}=conn) do
    case Sysdea.Models.Model.get(model_id) do
      nil -> false
      model -> {true, assign(conn, :model, model)}
    end
  end

  def user_has_access?(conn) do
    case {get_session(conn, :user), conn.assigns[:model]} do
      {%{admin: true}, _} -> true
      {%{id: user_id}, %{user_id: user_id}} -> true
      _ -> false
    end
  end

  # Properties

  def last_modified(%{assigns: %{model: %{last_modified: t}}}) do
    {{t.year, t.month, t.day}, {t.hour, t.min, t.sec}}
  end

  # Representation methods

  def as_json(conn) do
    conn.assigns.model
    |> Sysdea.Models.Model.json
    |> Poison.encode!
  end

  def as_html(conn) do
    # user_data = case get_session(conn, :user) do
    #               nil -> nil
    #               user -> Sysdea.Models.User.json(user)
    #             end
    # render conn, "index.html", user_data: user_data
    resp conn, 200, "MY HTML"
  end

  # Modification methods

  def post(%{params: params}=conn) do
    model = Sysdea.Models.Model.create(user: get_session(conn, :user),
                                       name: params.name,
                                       data: params.model_data)
    url = Sysdea.Router.Helpers.model_path(:get, model.uuid)
    assign(conn, :location, url)
  end

  def delete(conn) do
    Sysdea.Repo.delete(conn.assigns.model)
    conn
  end

  def patch(%{assigns: %{model: model}}=conn) do
    if conn.params[:name] do
      model = %{model | name: conn.params[:name]}
    end
    if conn.params[:model_data] do
      model = %{model | model_data: conn.params[:model_data]}
    end
    assign(conn, :model, Sysdea.Repo.update(model))
  end
end
