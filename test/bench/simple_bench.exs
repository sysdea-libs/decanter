defmodule SimpleBench.Get do
  use Decanter

  plug :serve
end

defmodule SimpleBench.FromExists do
  use Decanter

  plug :serve

  @entry_point :exists?
end

defmodule SimpleBench.Post do
  use Decanter

  plug :serve

  def post(conn), do: conn
end

defmodule SimpleBench.ConNeg do
  use Decanter

  plug :serve

  @available_media_types ["text/html", "application/json"]
end

defmodule SimpleBench do
  use Plug.Test
  use DecanterTest

  def print_time(label, {s_megasec, s_sec, s_usec}, {f_megasec, f_sec, f_usec}) do
    t = (f_megasec - s_megasec) * 1000000 + f_sec - s_sec + (f_usec - s_usec) / 1000000
    IO.inspect {label, t}
  end

  test "simple tests" do
    get = conn(:get, "/")
    start = :erlang.now
    for _ <- 0..10000 do
      SimpleBench.Get.call(get, nil)
    end
    finish = :erlang.now
    assert %{resp_body: "OK",
             status: 200} = rawrequest(SimpleBench.Get, get)
    print_time "10k get", start, finish

    post = conn(:post, "/")
    start = :erlang.now
    for _ <- 0..10000 do
      SimpleBench.Post.call(post, nil)
    end
    finish = :erlang.now
    assert %{resp_body: "",
             status: 201} = rawrequest(SimpleBench.Post, post)
    print_time "10k post", start, finish

    conneg = put_req_header(conn(:get, "/"), "accept",
                "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8")
    start = :erlang.now
    for _ <- 0..3000 do
      SimpleBench.ConNeg.call(conneg, nil)
    end
    finish = :erlang.now

    assert %{resp_body: "OK",
             status: 200,
             resp_headers: %{"Content-Type" => "text/html"}}
           = rawrequest(SimpleBench.ConNeg, conneg)
    print_time "3k conneg", start, finish

    get = conn(:get, "/")
    start = :erlang.now
    for _ <- 0..100000 do
      SimpleBench.FromExists.call(get, nil)
    end
    finish = :erlang.now
    assert %{resp_body: "OK",
             status: 200} = rawrequest(SimpleBench.FromExists, get)
    print_time "100k from_exists", start, finish
  end
end
