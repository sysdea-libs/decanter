ExUnit.start()

defmodule DecanterTest do
  use Plug.Test

  defmacro __using__(_) do
    quote do
      import DecanterTest
      use ExUnit.Case
    end
  end

  def test_conn(module, method, headers, assigns) do
    c = Enum.reduce(headers, conn(method, "/"), fn ({k, v}, conn) ->
      put_req_header(conn, k, v)
    end)

    apply(module, :call, [%{c | assigns: assigns}, nil])
  end

  defmacro rawrequest(module, conn) do
    quote do
      resp = unquote(module).call(unquote(conn), nil)
      %{resp | resp_headers: Enum.into(resp.resp_headers, %{})}
    end
  end

  def request(module, method, headers, assigns \\ %{}) do
    resp = test_conn(module, method, headers, assigns)
    %{resp | resp_headers: Enum.into(resp.resp_headers, %{})}
  end

  def testreq(module, method, opts \\ []) do
    headers = Keyword.get(opts, :headers, %{})
    assigns = Keyword.get(opts, :assigns, %{})
    params = Keyword.get(opts, :params, %{})
    path = Keyword.get(opts, :path, "/")

    c = conn(method, path)
    c = Enum.reduce(headers, c, fn ({k, v}, conn) ->
      put_req_header(conn, k, v)
    end)

    c = %{c | assigns: assigns, params: params}

    apply(module, :call, [c, nil])
  end
end
