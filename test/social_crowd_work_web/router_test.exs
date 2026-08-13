defmodule SocialCrowdWorkWeb.RouterTest do
  use ExUnit.Case, async: true

  test "participant launch routes expose launch_token outside admin live sessions" do
    routes = SocialCrowdWorkWeb.Router.__routes__()

    assert_route(routes, :delete, "/participate/:launch_token/decline", :decline)
    assert_route(routes, :get, "/participate/:launch_token/complete", :complete)

    assert %{metadata: metadata} =
             Enum.find(routes, &(&1.verb == :get and &1.path == "/participate/:launch_token"))

    assert {SocialCrowdWorkWeb.ParticipantLive, nil, _options, %{name: :default}} =
             metadata.phoenix_live_view
  end

  defp assert_route(routes, verb, path, plug_opts) do
    assert Enum.any?(routes, fn route ->
             route.verb == verb and route.path == path and route.plug_opts == plug_opts
           end)
  end
end
