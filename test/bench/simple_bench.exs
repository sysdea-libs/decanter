defmodule SimpleBench.Get do
  use Decanter

  plug :serve
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

    conneg = put_req_header(conn(:get, "/"), "accept", "application/*")
    start = :erlang.now
    for _ <- 0..10000 do
      SimpleBench.ConNeg.call(conneg, nil)
    end
    finish = :erlang.now

    assert %{resp_body: "OK",
             status: 200,
             resp_headers: %{"Content-Type" => "application/json"}}
           = rawrequest(SimpleBench.ConNeg, conneg)
    print_time "10k conneg", start, finish
  end
end
