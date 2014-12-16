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

  defmacro request(module, method, headers, assigns \\ Macro.escape(%{})) do
    quote do
      resp = test_conn(unquote(module), unquote(method), unquote(headers), unquote(assigns))
      %{resp | resp_headers: Enum.into(resp.resp_headers, %{})}
    end
  end
end
