defmodule PostGetPipelineTest.R do
  use Decanter.Pipeline
  import Decanter.Pipeline
  import Plug.Conn

  plug :decant

  decanter :start do
    negotiate media_type: ["text/html", "application/json"],
              charset: ["utf-8"],
              language: ["*"]

    property :entity
    property :last_modified
    property :etag

    method :get
    method :post
  end

  def etag(_conn) do
    1635
  end

  def last_modified(_conn) do
    {{2014, 12, 13}, {11, 36, 32}}
  end

  def entity(%{assigns: %{media_type: "text/html"}}=conn) do
    assign(conn, :entity, "HELLO")
  end
  def entity(%{assigns: %{media_type: "application/json"}}=conn) do
    assign(conn, :entity, ~s({"message": "HELLO"}))
  end

  def post(conn) do
    conn
  end
end

defmodule PostGetPipelineTest do
  use DecanterTest

  test "basics" do
    assert %{status: 200,
             resp_body: "HELLO"}
           = request(PostGetPipelineTest.R, :get, %{})

    assert %{status: 200,
             resp_body: "HELLO"}
           = request(PostGetPipelineTest.R, :post, %{})
  end

  test "methods (405/options)" do
    assert %{status: 405,
             resp_body: "Method not allowed.",
             resp_headers: %{"Allow" => "GET,POST"}}
           = request(PostGetPipelineTest.R, :patch, %{})

    assert %{status: 200,
             resp_body: "",
             resp_headers: %{"Allow" => "GET,POST,OPTIONS"}}
           = request(PostGetPipelineTest.R, :options, %{})
  end

  test "vary" do
    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"Vary" => "Accept"}}
           = request(PostGetPipelineTest.R, :get, %{})

    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"Vary" => "Accept-Language,Accept"}}
           = request(PostGetPipelineTest.R, :get, %{"accept-language" => "en"})
  end

  test "accept/charset" do
    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Content-Type" => "text/html;charset=utf-8",
                             "Vary" => "Accept-Charset,Accept"}}
           = request(PostGetPipelineTest.R, :get,
                     %{"accept" => "text/*",
                       "accept-charset" => "utf-8"})

    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Content-Type" => "text/html;charset=utf-8",
                             "Vary" => "Accept-Charset,Accept"}}
           = request(PostGetPipelineTest.R, :get,
                     %{"accept" => "text/html",
                       "accept-charset" => "utf-8"})

    assert %{status: 200,
             resp_body: ~s({"message": "HELLO"}),
             resp_headers: %{"ETag" => ~s("1635"),
                             "Content-Type" => "application/json;charset=utf-8",
                             "Vary" => "Accept-Charset,Accept"}}
           = request(PostGetPipelineTest.R, :get,
                     %{"accept" => "application/json",
                       "accept-charset" => "utf-8"})

    assert %{status: 406,
             resp_body: "No acceptable resource available."}
           = request(PostGetPipelineTest.R, :get, %{"accept" => "text/xml"})

    assert %{status: 406,
             resp_body: "No acceptable resource available."}
           = request(PostGetPipelineTest.R, :get, %{"accept-charset" => "utf-919"})
  end

  test "last_modified" do
    assert %{status: 200,
             resp_headers: %{"ETag" => ~s("1635"),
                             "Last-Modified" => "Sat, 13 Dec 2014 11:36:32 GMT"}}
          = request(PostGetPipelineTest.R, :get, %{})

    assert %{status: 304,
             resp_body: "",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Last-Modified" => "Sat, 13 Dec 2014 11:36:32 GMT"}}
          = request(PostGetPipelineTest.R, :get,
                    %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:32 GMT"})

    assert %{status: 200,
             resp_body: "HELLO",
             resp_headers: %{"ETag" => ~s("1635"),
                             "Last-Modified" => "Sat, 13 Dec 2014 11:36:32 GMT"}}
          = request(PostGetPipelineTest.R, :get,
                    %{"if-modified-since" => "Sat, 13 Dec 2014 11:36:00 GMT"})
  end

  test "etags" do
    assert %{status: 304,
             resp_body: ""}
           = request(PostGetPipelineTest.R, :get, %{"if-none-match" => ~s("1635")})

    assert %{status: 200,
             resp_body: "HELLO"}
           = request(PostGetPipelineTest.R, :get, %{"if-none-match" => ~s("1636")})
  end
end
