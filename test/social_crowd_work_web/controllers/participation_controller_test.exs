defmodule SocialCrowdWorkWeb.ParticipationControllerTest do
  use SocialCrowdWorkWeb.ConnCase, async: true

  import SocialCrowdWork.Fixtures

  test "stores verified Prolific context in an encrypted session and removes it from the URL", %{
    conn: conn
  } do
    condition = condition_fixture()
    attrs = participation_attrs(condition)

    conn = get(conn, entry_path(condition, attrs))

    assert redirected_to(conn) == ~p"/participate"
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]

    assert get_session(conn, "participant_context") == %{
             "condition_id" => condition.id,
             "prolific_participant_id" => attrs.prolific_participant_id,
             "prolific_study_id" => attrs.prolific_study_id,
             "prolific_session_id" => attrs.prolific_session_id
           }

    cookie_header = conn |> get_resp_header("set-cookie") |> Enum.join(";")
    refute cookie_header =~ attrs.prolific_participant_id
    refute cookie_header =~ attrs.prolific_session_id
    assert cookie_header =~ "HttpOnly"
    assert cookie_header =~ "SameSite=Lax"
  end

  test "rejects missing Prolific parameters without creating a session", %{conn: conn} do
    condition = condition_fixture()

    conn =
      get(
        conn,
        ~p"/participate/#{condition.entry_token}?#{%{"PROLIFIC_PID" => "participant", "STUDY_ID" => condition.prolific_study_id}}"
      )

    assert response(conn, 400)
    assert get_session(conn, "participant_context") == nil
  end

  test "rejects unknown conditions and mismatched Prolific studies", %{conn: conn} do
    attrs = %{
      prolific_participant_id: "participant",
      prolific_study_id: "study",
      prolific_session_id: "session"
    }

    assert conn |> get(entry_path(%{entry_token: "unknown"}, attrs)) |> response(404)

    condition = condition_fixture()
    wrong_study_attrs = %{attrs | prolific_study_id: "wrong-study"}
    assert conn |> recycle() |> get(entry_path(condition, wrong_study_attrs)) |> response(400)
  end

  test "declining clears the temporary participant session", %{conn: conn} do
    condition = condition_fixture()
    attrs = participation_attrs(condition)

    conn =
      conn |> get(entry_path(condition, attrs)) |> recycle() |> get(~p"/participate/declined")

    assert response(conn, 200)
    assert get_session(conn, "participant_context") == nil
  end

  defp entry_path(condition, attrs) do
    ~p"/participate/#{condition.entry_token}?#{%{"PROLIFIC_PID" => attrs.prolific_participant_id, "STUDY_ID" => attrs.prolific_study_id, "SESSION_ID" => attrs.prolific_session_id}}"
  end
end
