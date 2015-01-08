# json is authenticated, handles PATCH/GET/DELETE
# PATCH/GET/DELETE should 404 if not present
# PATCH should return a the new entity
# DELETE should 204
# should support caching via last modified date

# html version is unauthenticated
# embeds a representation of the user if logged in
# should not be cacheable

defmodule PipelineTest.R do
  use Decanter.Pipeline
  import Decanter.Pipeline
  import Plug.Conn

  @dummy_models %{"1" => %{json: ~s({name: "Model 1"}),
                           user_id: 1,
                           last_modified: {{2015,1,1},{0,0,0}}},
                  "2" => %{json: ~s({name: "Model 2"}),
                           user_id: 2,
                           last_modified: {{2015,1,1},{0,0,0}}}}

  @dummy_sessions %{"s1" => %{id: 1, admin: true},
                    "s2" => %{id: 2, admin: false}}

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
    case @dummy_models[model_id] do
      nil -> false
      model -> {true, assign(conn, :model, model)}
    end
  end

  def user_has_access?(conn) do
    case {@dummy_sessions[conn.params["session_id"]], conn.assigns[:model]} do
      {%{admin: true}, _} -> true
      {%{id: user_id}, %{user_id: user_id}} -> true
      _ -> false
    end
  end

  # Properties

  def last_modified(%{assigns: %{model: %{last_modified: t}}}) do
    t
  end

  # Representation methods

  def as_json(conn) do
    conn.assigns.model.json
  end

  def as_html(_conn) do
    "HTML PAGE"
  end

  # Modification methods

  def post(conn) do
    url = "/path/to/new/model"
    assign(conn, :location, url)
  end

  def delete(conn) do
    conn
  end

  def patch(conn) do
    conn
  end
end

defmodule PipelineTest do
  use DecanterTest

  test "html" do
    assert %{status: 200,
             resp_body: "HTML PAGE"}
           = testreq(PipelineTest.R, :get)

    assert %{status: 405,
             resp_body: "Method not allowed."}
           = testreq(PipelineTest.R, :post)
  end

  test "json" do
    assert %{status: 403,
             resp_body: "Forbidden."}
           = testreq(PipelineTest.R, :get,
              headers: %{"accept" => "application/json"},
              params: %{"model_id" => "1"})

    assert %{status: 403,
             resp_body: "Forbidden."}
           = testreq(PipelineTest.R, :get,
              headers: %{"accept" => "application/json"},
              params: %{"model_id" => "1",
                        "session_id" => "s2"})

    assert %{status: 200,
             resp_body: ~s({name: "Model 1"})}
           = testreq(PipelineTest.R, :get,
              headers: %{"accept" => "application/json"},
              params: %{"model_id" => "1",
                        "session_id" => "s1"})
  end
end
