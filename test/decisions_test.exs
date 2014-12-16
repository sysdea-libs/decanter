defmodule DecisionsTest.R do
  use Decanter

  plug :serve

  def check_setting(conn, setting, default) do
    if Map.has_key?(conn.assigns, setting) do
      conn.assigns[setting]
    else
      default
    end
  end

  decide :allowed?, do: check_setting(conn, :allowed?, true)
  decide :authorized?, do: check_setting(conn, :authorized?, true)
  decide :can_post_to_gone?, do: check_setting(conn, :can_post_to_gone?, true)
  decide :can_post_to_missing?, do: check_setting(conn, :can_post_to_missing?, true)
  decide :can_put_to_missing?, do: check_setting(conn, :can_put_to_missing?, true)
  decide :conflict?, do: check_setting(conn, :conflict?, false)
  decide :create_enacted?, do: check_setting(conn, :create_enacted?, true)
  decide :delete_enacted?, do: check_setting(conn, :delete_enacted?, true)
  decide :existed?, do: check_setting(conn, :existed?, false)
  decide :exists?, do: check_setting(conn, :exists?, true)
  decide :known_content_type?, do: check_setting(conn, :known_content_type?, true)
  decide :malformed?, do: check_setting(conn, :malformed?, false)
  decide :moved_permanently?, do: check_setting(conn, :moved_permanently?, false)
  decide :moved_temporarily?, do: check_setting(conn, :moved_temporarily?, false)
  decide :multiple_representations?, do: check_setting(conn, :multiple_representations?, false)
  decide :new?, do: check_setting(conn, :new?, true)
  decide :redirect_on_create?, do: check_setting(conn, :redirect_on_create?, false)
  decide :processable?, do: check_setting(conn, :processable?, true)
  decide :put_to_different_url?, do: check_setting(conn, :put_to_different_url?, false)
  decide :respond_with_entity?, do: check_setting(conn, :respond_with_entity?, false)
  decide :service_available?, do: check_setting(conn, :service_available?, true)
  decide :uri_too_long?, do: check_setting(conn, :uri_too_long?, false)
  decide :valid_content_header?, do: check_setting(conn, :valid_content_header?, true)
  decide :valid_entity_length?, do: check_setting(conn, :valid_entity_length?, true)

  def put(conn), do: conn
  def post(conn), do: conn
  def patch(conn), do: conn
  def delete(conn), do: conn

  dynamic :handle_unprocessable_entity
end

defmodule DecisionsTest do
  use DecanterTest

  test "simple decisions" do
    assert %{status: 403,
             resp_body: "Forbidden."}
           = request(DecisionsTest.R, :get, %{}, %{allowed?: false})

    assert %{status: 401,
             resp_body: "Not authorized."}
           = request(DecisionsTest.R, :get, %{}, %{authorized?: false})

    assert %{status: 410,
             resp_body: "Resource is gone."}
           = request(DecisionsTest.R, :post, %{}, %{can_post_to_gone?: false,
                                                    exists?: false,
                                                    existed?: true})

    assert %{status: 404,
             resp_body: "Resource not found."}
           = request(DecisionsTest.R, :post, %{}, %{can_post_to_missing?: false,
                                                    exists?: false,
                                                    existed?: false})

    assert %{status: 501,
             resp_body: "Not implemented."}
           = request(DecisionsTest.R, :put, %{}, %{can_put_to_missing?: false,
                                                   exists?: false,
                                                   existed?: false})

    assert %{status: 409,
             resp_body: "Conflict."}
           = request(DecisionsTest.R, :put, %{}, %{conflict?: true})

    assert %{status: 202,
             resp_body: "Accepted."}
           = request(DecisionsTest.R, :delete, %{}, %{delete_enacted?: false})

    assert %{status: 301,
             resp_body: ""}
           = request(DecisionsTest.R, :get, %{}, %{exists?: false,
                                                   existed?: true,
                                                   moved_permanently?: true})

    assert %{status: 307,
             resp_body: ""}
           = request(DecisionsTest.R, :get, %{}, %{exists?: false,
                                                   existed?: true,
                                                   moved_temporarily?: true})

    assert %{status: 415,
             resp_body: "Unsupported media type."}
           = request(DecisionsTest.R, :put, %{}, %{known_content_type?: false})

    assert %{status: 400,
             resp_body: "Bad request."}
           = request(DecisionsTest.R, :put, %{}, %{malformed?: true})

    assert %{status: 300,
             resp_body: ""}
           = request(DecisionsTest.R, :get, %{}, %{multiple_representations?: true})

    assert %{status: 201,
             resp_body: ""}
           = request(DecisionsTest.R, :put, %{}, %{new?: true})

    assert %{status: 202,
             resp_body: "Accepted."}
           = request(DecisionsTest.R, :put, %{}, %{new?: true,
                                                   create_enacted?: false})

    assert %{status: 204,
             resp_body: ""}
           = request(DecisionsTest.R, :put, %{}, %{new?: false})

    assert %{status: 200,
             resp_body: "OK"}
           = request(DecisionsTest.R, :put, %{}, %{new?: false,
                                                   respond_with_entity?: true})

    assert %{status: 303,
             resp_body: ""}
           = request(DecisionsTest.R, :post, %{}, %{redirect_on_create?: true})

    assert %{status: 201,
             resp_body: ""}
           = request(DecisionsTest.R, :put, %{}, %{redirect_on_create?: true})

    assert %{status: 422,
             resp_body: "Unprocessable entity."}
           = request(DecisionsTest.R, :get, %{}, %{processable?: false})

    assert %{status: 301,
             resp_body: ""}
           = request(DecisionsTest.R, :put, %{}, %{exists?: false,
                                                   put_to_different_url?: true})

    assert %{status: 503,
             resp_body: "Service not available."}
           = request(DecisionsTest.R, :get, %{}, %{service_available?: false})

    assert %{status: 414,
             resp_body: "Request URI too long."}
           = request(DecisionsTest.R, :put, %{}, %{uri_too_long?: true})

    assert %{status: 501,
             resp_body: "Not implemented."}
           = request(DecisionsTest.R, :put, %{}, %{valid_content_header?: false})

    assert %{status: 413,
             resp_body: "Request entity too large."}
           = request(DecisionsTest.R, :put, %{}, %{valid_entity_length?: false})
  end

  test "atom redirect" do
    assert %{status: 422,
             resp_body: "Unprocessable entity."}
           = request(DecisionsTest.R, :get, %{}, %{allowed?: :handle_unprocessable_entity})
  end
end
