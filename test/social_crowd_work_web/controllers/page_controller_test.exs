defmodule SocialCrowdWorkWeb.PageControllerTest do
  use SocialCrowdWorkWeb.ConnCase

  test "GET / redirects to the admin panel", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/admin"
  end

  test "GET /documents/research_study_privacy_notice.pdf", %{conn: conn} do
    conn = get(conn, ~p"/documents/research_study_privacy_notice.pdf")

    assert ["application/pdf"] = get_resp_header(conn, "content-type")
    assert "%PDF-" <> _document = response(conn, 200)
  end
end
