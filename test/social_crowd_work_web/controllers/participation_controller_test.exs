defmodule SocialCrowdWorkWeb.ParticipationControllerTest do
  use SocialCrowdWorkWeb.ConnCase, async: true

  import SocialCrowdWork.Fixtures

  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.DataCollection.{ParticipantLaunch, Participation}
  alias SocialCrowdWork.Repo

  test "creates a database launch and redirects without participant session state", %{conn: conn} do
    condition = condition_fixture()
    attrs = participation_attrs(condition)

    conn = get(conn, entry_path(condition, attrs))
    participant_path = redirected_to(conn)
    launch_token = token_from_path(participant_path)

    assert participant_path =~ ~r|^/participate/[A-Za-z0-9_-]{43}$|
    refute participant_path =~ attrs.prolific_participant_id
    refute participant_path =~ attrs.prolific_session_id
    assert get_session(conn) == %{}
    assert Repo.aggregate(ParticipantLaunch, :count) == 1

    assert {:ok, %{launch: launch, condition: resolved, participation: nil}} =
             DataCollection.resolve_participant_launch(launch_token)

    assert resolved.id == condition.id
    assert launch.prolific_participant_id == attrs.prolific_participant_id
    assert launch.prolific_study_id == attrs.prolific_study_id
    assert launch.prolific_session_id == attrs.prolific_session_id
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  test "supports more than two studies and gives duplicate entries fresh paths", %{conn: conn} do
    launches =
      for _index <- 1..3 do
        condition = condition_fixture()
        attrs = participation_attrs(condition)
        path = conn |> recycle() |> get(entry_path(condition, attrs)) |> redirected_to()
        {condition, attrs, path}
      end

    assert launches |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> length() == 3
    assert Repo.aggregate(ParticipantLaunch, :count) == 3

    {condition, attrs, first_path} = List.first(launches)
    repeated = conn |> recycle() |> get(entry_path(condition, attrs)) |> redirected_to()

    assert repeated != first_path
    assert Repo.aggregate(ParticipantLaunch, :count) == 4

    assert {:ok, _context} =
             DataCollection.resolve_participant_launch(token_from_path(first_path))

    assert {:ok, _context} = DataCollection.resolve_participant_launch(token_from_path(repeated))
  end

  test "rejects invalid parameters, unknown conditions, and study mismatches without a launch", %{
    conn: conn
  } do
    condition = condition_fixture()

    invalid =
      get(
        conn,
        ~p"/enter/#{condition.entry_token}?#{%{"PROLIFIC_PID" => "participant", "STUDY_ID" => condition.prolific_study_id}}"
      )

    assert redirected_to(invalid) == ~p"/participate/error?reason=invalid_prolific_parameters"

    attrs = participation_attrs(condition)
    unknown = conn |> recycle() |> get(entry_path(%{entry_token: "unknown"}, attrs))
    assert redirected_to(unknown) == ~p"/participate/error?reason=unknown_condition"

    mismatch_attrs = %{attrs | prolific_study_id: "wrong-study"}
    mismatch = conn |> recycle() |> get(entry_path(condition, mismatch_attrs))
    assert redirected_to(mismatch) == ~p"/participate/error?reason=prolific_study_mismatch"
    assert Repo.aggregate(ParticipantLaunch, :count) == 0
  end

  test "DELETE decline consumes only the selected pre-consent launch", %{conn: conn} do
    first_condition = condition_fixture()
    second_condition = condition_fixture()
    first_path = launch_path(conn, first_condition, participation_attrs(first_condition))
    second_path = launch_path(conn, second_condition, participation_attrs(second_condition))
    first_token = token_from_path(first_path)
    second_token = token_from_path(second_path)

    declined_conn = delete(recycle(conn), ~p"/participate/#{first_token}/decline")

    assert redirected_to(declined_conn) == ~p"/participate/declined"
    assert {:error, :invalid_launch} = DataCollection.resolve_participant_launch(first_token)
    assert {:ok, _context} = DataCollection.resolve_participant_launch(second_token)
    assert Repo.aggregate(ParticipantLaunch, :count) == 1
  end

  test "invalid and already-consented declines return to the participant URL", %{conn: conn} do
    invalid_token = valid_unstored_token()
    invalid_conn = delete(conn, ~p"/participate/#{invalid_token}/decline")
    assert redirected_to(invalid_conn) == ~p"/participate/#{invalid_token}"

    condition = condition_fixture()
    run_fixture(condition)
    launch_path = launch_path(conn, condition, participation_attrs(condition))
    launch_token = token_from_path(launch_path)

    assert {:ok, %Participation{}} =
             DataCollection.consent_and_assign_run(launch_token, condition.consent_key)

    consented_conn = delete(recycle(conn), ~p"/participate/#{launch_token}/decline")
    assert redirected_to(consented_conn) == launch_path

    assert {:ok, %{participation: %Participation{}}} =
             DataCollection.resolve_participant_launch(launch_token)
  end

  test "completion consumes completed launches and redirects to Prolific", %{conn: conn} do
    condition = condition_fixture()
    run = run_fixture(condition)
    launch_path = launch_path(conn, condition, participation_attrs(condition))
    launch_token = token_from_path(launch_path)
    [task] = run.tasks

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(launch_token, condition.consent_key)

    incomplete_conn = get(recycle(conn), ~p"/participate/#{launch_token}/complete")
    assert redirected_to(incomplete_conn) == launch_path

    assert {:ok, _response} =
             DataCollection.record_response(participation, task.id, "test-comparison.v1", :skip)

    assert {:ok, _completed} = DataCollection.complete_participation(participation)

    complete_conn = get(recycle(conn), ~p"/participate/#{launch_token}/complete")
    assert redirected_to(complete_conn) =~ condition.prolific_completion_code
    assert {:error, :invalid_launch} = DataCollection.resolve_participant_launch(launch_token)
    assert Repo.aggregate(ParticipantLaunch, :count) == 0

    consumed_conn = get(recycle(conn), ~p"/participate/#{launch_token}/complete")
    assert redirected_to(consumed_conn) == launch_path
  end

  defp entry_path(condition, attrs) do
    ~p"/enter/#{condition.entry_token}?#{%{"PROLIFIC_PID" => attrs.prolific_participant_id, "STUDY_ID" => attrs.prolific_study_id, "SESSION_ID" => attrs.prolific_session_id}}"
  end

  defp launch_path(conn, condition, attrs) do
    conn |> recycle() |> get(entry_path(condition, attrs)) |> redirected_to()
  end

  defp token_from_path(path), do: path |> String.split("/") |> List.last()

  defp valid_unstored_token do
    Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
  end
end
