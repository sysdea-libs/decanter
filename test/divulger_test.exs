defmodule DivulgerTest.R do
  use Divulger

  plug :serve

  def etag(_conn) do
    1635
  end

  def available_media_types, do: ["text/html", "application/json"]

  def handle_ok(%Plug.Conn{assigns: %{media_type: "text/html"}}) do
    "HELLO"
  end

  def handle_ok(%Plug.Conn{assigns: %{media_type: "application/json"}}) do
    ~s({"message": "HELLO"})
  end

  def last_modified(_conn) do
    {{2014, 12, 13}, {11, 36, 32}}
  end
end


defmodule DivulgerTest do
  use ExUnit.Case
  use Plug.Test

  def test_conn(module, method, headers) do
    c = Enum.reduce(headers, conn(method, "/"), fn ({k, v}, conn) ->
      put_req_header(conn, k, v)
    end)

    apply(module, :call, [c, nil])
  end

  test "basics" do
    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"}
           = test_conn(DivulgerTest.R, :get, %{})
  end

  test "accept/charset" do
    resp = test_conn(DivulgerTest.R, :get,
                      %{"accept" => "text/*",
                        "accept-charset" => "utf-8"})
    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"} = resp
    assert %{"ETag" => ~s("1635"),
             "Content-Type" => "text/html;charset=utf-8"} = Enum.into(resp.resp_headers, %{})

    resp = test_conn(DivulgerTest.R, :get,
                      %{"accept" => "text/html",
                        "accept-charset" => "utf-8"})
    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"} = resp
    assert %{"ETag" => ~s("1635"),
             "Content-Type" => "text/html;charset=utf-8"} = Enum.into(resp.resp_headers, %{})

    resp = test_conn(DivulgerTest.R, :get,
                      %{"accept" => "application/json",
                        "accept-charset" => "utf-8"})
    assert %Plug.Conn{status: 200,
                      resp_body: ~s({"message": "HELLO"})} = resp
    assert %{"ETag" => ~s("1635"),
             "Content-Type" => "application/json;charset=utf-8"} = Enum.into(resp.resp_headers, %{})

    assert %Plug.Conn{status: 406,
                      resp_body: "No acceptable resource available."}
           = test_conn(DivulgerTest.R, :get, %{"accept" => "text/xml"})

    assert %Plug.Conn{status: 406,
                      resp_body: "No acceptable resource available."}
           = test_conn(DivulgerTest.R, :get, %{"accept-charset" => "utf-919"})

  end

  test "last_modified" do
    assert %Plug.Conn{status: 304,
                      resp_body: ""}
           = test_conn(DivulgerTest.R, :get,
                       %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:32 GMT"})

    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"}
           = test_conn(DivulgerTest.R, :get,
                       %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:00 GMT"})
  end

  test "etags" do
    assert %Plug.Conn{status: 304,
                      resp_body: ""}
           = test_conn(DivulgerTest.R, :get, %{"if-none-match" => ~s("1635")})

    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"}
           = test_conn(DivulgerTest.R, :get, %{"if-none-match" => ~s("1636")})
  end
end
