defmodule SocialCrowdWorkWeb.PageControllerTest do
  use SocialCrowdWorkWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET /documents/research_study_privacy_notice.pdf", %{conn: conn} do
    conn = get(conn, ~p"/documents/research_study_privacy_notice.pdf")

    assert ["application/pdf"] = get_resp_header(conn, "content-type")
    assert "%PDF-" <> _document = response(conn, 200)
  end
end
