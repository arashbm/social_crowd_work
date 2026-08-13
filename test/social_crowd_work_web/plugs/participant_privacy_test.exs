defmodule SocialCrowdWorkWeb.Plugs.ParticipantPrivacyTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias SocialCrowdWorkWeb.Plugs.ParticipantPrivacy

  test "prevents participant responses from being cached, referred, or indexed" do
    conn = ParticipantPrivacy.call(conn(:get, "/participate/token"), [])

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "pragma") == ["no-cache"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "x-robots-tag") == ["noindex,nofollow,noarchive"]
  end
end
