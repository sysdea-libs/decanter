defmodule DisabledTest.R do
  use Decanter

  plug :serve

  decide :service_available?, do: false
end

defmodule DisabledTest do
  use DecanterTest

  test "service_available?" do
    assert %{status: 503,
             resp_body: "Service not available."}
           = request(DisabledTest.R, :get, %{})
  end
end
