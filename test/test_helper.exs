ExUnit.start()

defmodule DecanterTest do
  use Plug.Test

  defmacro __using__(_) do
    quote do
      import DecanterTest
      use ExUnit.Case
    end
  end

  def test_conn(module, method, headers) do
    c = Enum.reduce(headers, conn(method, "/"), fn ({k, v}, conn) ->
      put_req_header(conn, k, v)
    end)

    apply(module, :call, [c, nil])
  end

  defmacro request(module, method, headers) do
    quote do
      resp = test_conn(unquote(module), unquote(method), unquote(headers))
      %{resp | resp_headers: Enum.into(resp.resp_headers, %{})}
    end
  end
end
