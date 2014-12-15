defmodule PostGetTest.R do
  use Decanter

  plug :serve

  def etag(_conn) do
    1635
  end

  @available_media_types ["text/html", "application/json"]
  @available_charsets ["utf-8"]

  def handle_ok(%Plug.Conn{assigns: %{media_type: "text/html"}}=conn) do
    put_resp(conn, "HELLO")
  end

  def handle_ok(%Plug.Conn{assigns: %{media_type: "application/json"}}=conn) do
    put_resp(conn, ~s({"message": "HELLO"}))
  end

  def last_modified(_conn) do
    {{2014, 12, 13}, {11, 36, 32}}
  end

  def post!(conn) do
    conn
  end
end

defmodule PostGetTest do
  use DecanterTest

  test "basics" do
    assert %{status: 200,
             resp_body: "HELLO"}
           = request(PostGetTest.R, :get, %{})
  end

  test "methods (405/options)" do
    assert %{status: 405,
             resp_body: "Method not allowed.",
             resp_headers: %{"Allow" => "POST,GET,OPTIONS"}}
           = request(PostGetTest.R, :patch, %{})

    assert %{status: 200,
             resp_body: "",
             resp_headers: %{"Allow" => "POST,GET,OPTIONS"}}
           = request(PostGetTest.R, :options, %{})
  end

  test "vary" do
    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"Vary" => "Accept"}}
           = request(PostGetTest.R, :get, %{})
  end

  test "accept/charset" do
    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Content-Type" => "text/html;charset=utf-8",
                             "Vary" => "Accept-Charset,Accept"}}
           = request(PostGetTest.R, :get,
                     %{"accept" => "text/*",
                       "accept-charset" => "utf-8"})

    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Content-Type" => "text/html;charset=utf-8",
                             "Vary" => "Accept-Charset,Accept"}}
           = request(PostGetTest.R, :get,
                     %{"accept" => "text/html",
                       "accept-charset" => "utf-8"})

    assert %{status: 200,
             resp_body: ~s({"message": "HELLO"}),
             resp_headers: %{"ETag" => ~s("1635"),
                             "Content-Type" => "application/json;charset=utf-8",
                             "Vary" => "Accept-Charset,Accept"}}
           = request(PostGetTest.R, :get,
                     %{"accept" => "application/json",
                       "accept-charset" => "utf-8"})

    assert %{status: 406,
             resp_body: "No acceptable resource available."}
           = request(PostGetTest.R, :get, %{"accept" => "text/xml"})

    assert %{status: 406,
             resp_body: "No acceptable resource available."}
           = request(PostGetTest.R, :get, %{"accept-charset" => "utf-919"})
  end

  test "last_modified" do
    assert %{status: 200,
             resp_headers: %{"ETag" => ~s("1635"),
                             "Last-Modified" => "Sat, 13 Dec 2014 11:36:32 GMT"}}
          = request(PostGetTest.R, :get, %{})

    assert %{status: 304,
             resp_body: "",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Last-Modified" => "Sat, 13 Dec 2014 11:36:32 GMT"}}
          = request(PostGetTest.R, :get,
                    %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:32 GMT"})

    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Last-Modified" => "Sat, 13 Dec 2014 11:36:32 GMT"}}
          = request(PostGetTest.R, :get,
                    %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:00 GMT"})
  end

  test "etags" do
    assert %{status: 304,
             resp_body: ""}
           = request(PostGetTest.R, :get, %{"if-none-match" => ~s("1635")})

    assert %{status: 200,
             resp_body: "HELLO"}
           = request(PostGetTest.R, :get, %{"if-none-match" => ~s("1636")})
  end
end
