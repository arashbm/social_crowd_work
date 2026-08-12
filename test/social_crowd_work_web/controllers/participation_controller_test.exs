defmodule SocialCrowdWorkWeb.ParticipationControllerTest do
  use SocialCrowdWorkWeb.ConnCase, async: true

  import SocialCrowdWork.Fixtures

  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWorkWeb.ParticipantContexts

  test "stores an opaque participant context and removes identifiers from the URL", %{conn: conn} do
    condition = condition_fixture()
    attrs = participation_attrs(condition)

    conn = get(conn, entry_path(condition, attrs))
    participant_path = redirected_to(conn)
    assert participant_path =~ ~r|^/participate/[A-Za-z0-9_-]{43}$|
    refute participant_path =~ attrs.prolific_participant_id
    refute participant_path =~ attrs.prolific_session_id
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]

    [context] = get_session(conn, ParticipantContexts.session_key()) |> Map.values()

    assert context == %{
             "condition_id" => condition.id,
             "prolific_participant_id" => attrs.prolific_participant_id,
             "prolific_study_id" => attrs.prolific_study_id,
             "prolific_session_id" => attrs.prolific_session_id,
             "issued_at" => context["issued_at"]
           }

    assert is_integer(context["issued_at"])
    cookie_header = conn |> get_resp_header("set-cookie") |> Enum.join(";")
    refute cookie_header =~ attrs.prolific_participant_id
    refute cookie_header =~ attrs.prolific_session_id
    assert cookie_header =~ "HttpOnly"
    assert cookie_header =~ "SameSite=Lax"
  end

  test "keeps two studies independent and reuses an identical launch", %{conn: conn} do
    first_condition = condition_fixture()
    second_condition = condition_fixture()
    first_attrs = participation_attrs(first_condition)
    second_attrs = participation_attrs(second_condition)

    first_conn = get(conn, entry_path(first_condition, first_attrs))
    first_path = redirected_to(first_conn)

    second_conn = first_conn |> recycle() |> get(entry_path(second_condition, second_attrs))
    second_path = redirected_to(second_conn)

    assert first_path != second_path
    assert map_size(get_session(second_conn, ParticipantContexts.session_key())) == 2

    repeated_conn = second_conn |> recycle() |> get(entry_path(first_condition, first_attrs))
    assert redirected_to(repeated_conn) == first_path
    assert map_size(get_session(repeated_conn, ParticipantContexts.session_key())) == 2
  end

  test "two maximum-length contexts fit in a browser cookie", %{conn: conn} do
    long_value = String.duplicate("x", 255)

    conn =
      Enum.reduce(1..2, conn, fn index, conn ->
        condition = condition_fixture()

        attrs = %{
          prolific_participant_id: "#{index}" <> String.slice(long_value, 1..254),
          prolific_study_id: condition.prolific_study_id,
          prolific_session_id: "#{index}" <> String.slice(long_value, 1..254)
        }

        conn |> recycle() |> get(entry_path(condition, attrs))
      end)

    cookie_header = conn |> get_resp_header("set-cookie") |> Enum.join(";")
    assert byte_size(cookie_header) < 4_096
  end

  test "rejects a third fresh context without replacing the existing contexts", %{conn: conn} do
    {conn, paths} =
      Enum.reduce(1..2, {conn, []}, fn _index, {conn, paths} ->
        condition = condition_fixture()
        attrs = participation_attrs(condition)
        conn = conn |> recycle() |> get(entry_path(condition, attrs))
        {conn, [redirected_to(conn) | paths]}
      end)

    condition = condition_fixture()
    conn = conn |> recycle() |> get(entry_path(condition, participation_attrs(condition)))

    assert redirected_to(conn) == ~p"/participate/error?reason=capacity_reached"
    assert map_size(get_session(conn, ParticipantContexts.session_key())) == 2
    assert Enum.all?(paths, &String.starts_with?(&1, "/participate/"))
  end

  test "redirects invalid launches to a clean error URL without creating a context", %{conn: conn} do
    condition = condition_fixture()

    conn =
      get(
        conn,
        ~p"/enter/#{condition.entry_token}?#{%{"PROLIFIC_PID" => "participant", "STUDY_ID" => condition.prolific_study_id}}"
      )

    assert redirected_to(conn) == ~p"/participate/error?reason=invalid_prolific_parameters"
    assert get_session(conn, ParticipantContexts.session_key()) == nil

    error_conn = conn |> recycle() |> get(redirected_to(conn))
    assert html_response(error_conn, 200)
    assert get_resp_header(error_conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(error_conn, "cache-control") == ["no-store"]
  end

  test "redirects unknown conditions and study mismatches to clean errors", %{conn: conn} do
    attrs = %{
      prolific_participant_id: "participant",
      prolific_study_id: "study",
      prolific_session_id: "session"
    }

    unknown = get(conn, entry_path(%{entry_token: "unknown"}, attrs))
    assert redirected_to(unknown) == ~p"/participate/error?reason=unknown_condition"

    condition = condition_fixture()
    wrong_study_attrs = %{attrs | prolific_study_id: "wrong-study"}
    mismatch = conn |> recycle() |> get(entry_path(condition, wrong_study_attrs))
    assert redirected_to(mismatch) == ~p"/participate/error?reason=prolific_study_mismatch"
  end

  test "declining removes only the selected participant context", %{conn: conn} do
    first_condition = condition_fixture()
    second_condition = condition_fixture()
    first_conn = get(conn, entry_path(first_condition, participation_attrs(first_condition)))
    first_path = redirected_to(first_conn)

    second_conn =
      first_conn
      |> recycle()
      |> get(entry_path(second_condition, participation_attrs(second_condition)))

    second_path = redirected_to(second_conn)
    first_token = token_from_path(first_path)
    second_token = token_from_path(second_path)

    declined_conn =
      second_conn |> recycle() |> get(~p"/participate/#{first_token}/decline")

    assert redirected_to(declined_conn) == ~p"/participate/declined"
    contexts = get_session(declined_conn, ParticipantContexts.session_key())
    refute Map.has_key?(contexts, first_token)
    assert Map.has_key?(contexts, second_token)
  end

  test "completion removes its context and redirects only completed participations", %{conn: conn} do
    condition = condition_fixture()
    run = run_fixture(condition)
    attrs = participation_attrs(condition)
    entry_conn = get(conn, entry_path(condition, attrs))
    participant_path = redirected_to(entry_conn)
    token = token_from_path(participant_path)
    [task] = run.tasks

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, condition.consent_key)

    incomplete_conn = entry_conn |> recycle() |> get(~p"/participate/#{token}/complete")
    assert redirected_to(incomplete_conn) == participant_path

    assert {:ok, _response} = DataCollection.record_response(participation, task.id, :skip)
    assert {:ok, _completed} = DataCollection.complete_participation(participation)

    complete_conn = entry_conn |> recycle() |> get(~p"/participate/#{token}/complete")
    assert redirected_to(complete_conn) =~ condition.prolific_completion_code
    refute Map.has_key?(get_session(complete_conn, ParticipantContexts.session_key()), token)
  end

  defp entry_path(condition, attrs) do
    ~p"/enter/#{condition.entry_token}?#{%{"PROLIFIC_PID" => attrs.prolific_participant_id, "STUDY_ID" => attrs.prolific_study_id, "SESSION_ID" => attrs.prolific_session_id}}"
  end

  defp token_from_path(path), do: path |> String.split("/") |> List.last()
end
