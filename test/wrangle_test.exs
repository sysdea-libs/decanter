defmodule WrangleTest.R do
  use Wrangle

  plug :serve

  def etag(_conn) do
    1635
  end

  @available_media_types ["text/html", "application/json"]
  @available_charsets ["utf-8"]

  handle :ok, %Plug.Conn{assigns: %{media_type: "text/html"}} do
    "HELLO"
  end

  handle :ok, %Plug.Conn{assigns: %{media_type: "application/json"}} do
    ~s({"message": "HELLO"})
  end

  def last_modified(_conn) do
    {{2014, 12, 13}, {11, 36, 32}}
  end
end

defmodule WrangleTest.Disabled do
  use Wrangle

  plug :serve

  decide :service_available?, do: false
end


defmodule WrangleTest do
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
           = test_conn(WrangleTest.R, :get, %{})
  end

  test "accept/charset" do
    resp = test_conn(WrangleTest.R, :get,
                      %{"accept" => "text/*",
                        "accept-charset" => "utf-8"})
    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"} = resp
    assert %{"ETag" => ~s("1635"),
             "Content-Type" => "text/html;charset=utf-8"} = Enum.into(resp.resp_headers, %{})

    resp = test_conn(WrangleTest.R, :get,
                      %{"accept" => "text/html",
                        "accept-charset" => "utf-8"})
    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"} = resp
    assert %{"ETag" => ~s("1635"),
             "Content-Type" => "text/html;charset=utf-8"} = Enum.into(resp.resp_headers, %{})

    resp = test_conn(WrangleTest.R, :get,
                      %{"accept" => "application/json",
                        "accept-charset" => "utf-8"})
    assert %Plug.Conn{status: 200,
                      resp_body: ~s({"message": "HELLO"})} = resp
    assert %{"ETag" => ~s("1635"),
             "Content-Type" => "application/json;charset=utf-8"} = Enum.into(resp.resp_headers, %{})

    assert %Plug.Conn{status: 406,
                      resp_body: "No acceptable resource available."}
           = test_conn(WrangleTest.R, :get, %{"accept" => "text/xml"})

    assert %Plug.Conn{status: 406,
                      resp_body: "No acceptable resource available."}
           = test_conn(WrangleTest.R, :get, %{"accept-charset" => "utf-919"})

  end

  test "last_modified" do
    assert %Plug.Conn{status: 304,
                      resp_body: ""}
           = test_conn(WrangleTest.R, :get,
                       %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:32 GMT"})

    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"}
           = test_conn(WrangleTest.R, :get,
                       %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:00 GMT"})
  end

  test "etags" do
    assert %Plug.Conn{status: 304,
                      resp_body: ""}
           = test_conn(WrangleTest.R, :get, %{"if-none-match" => ~s("1635")})

    assert %Plug.Conn{status: 200,
                      resp_body: "HELLO"}
           = test_conn(WrangleTest.R, :get, %{"if-none-match" => ~s("1636")})
  end

  test "service_available?" do
    assert %Plug.Conn{status: 503,
                      resp_body: "Service not available."}
           = test_conn(WrangleTest.Disabled, :get, %{})
  end
end
