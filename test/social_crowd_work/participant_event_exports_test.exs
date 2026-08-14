defmodule SocialCrowdWork.ParticipantEventExportsTest do
  use SocialCrowdWork.DataCase, async: true

  import SocialCrowdWork.Fixtures

  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.DataCollection.ParticipantEvent
  alias SocialCrowdWork.ParticipantEventExports
  alias SocialCrowdWork.Repo

  test "exports one raw event per line with joined context and all event fields" do
    condition = condition_fixture()
    run = run_fixture(condition)
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    [task] = run.tasks
    client_session_id = Ecto.UUID.generate()
    event_id = Ecto.UUID.generate()
    occurred_at = ~U[2026-08-14 08:00:00.123456Z]
    received_at = ~U[2026-08-14 08:00:01.123456Z]

    insert_event(participation,
      task_id: task.id,
      question_key: "test-comparison.v1",
      kind: :question_exposure,
      event_id: event_id,
      client_session_id: client_session_id,
      sequence: 7,
      client_elapsed_ms: 1_250,
      duration_ms: 400,
      client_occurred_at: occurred_at,
      server_received_at: received_at,
      metadata: %{"reason" => "question_changed"}
    )

    assert {:ok, [line]} = collect_jsonl(condition_key: condition.key)
    record = Jason.decode!(line)

    assert record["schema_version"] == "1"
    assert record["condition"]["key"] == condition.key
    assert record["run"]["key"] == run.external_key
    assert record["participation"]["id"] == participation.id
    assert record["participation"]["prolific_participant_id"] == attrs.prolific_participant_id
    assert record["participation"]["prolific_study_id"] == attrs.prolific_study_id
    assert record["participation"]["prolific_session_id"] == attrs.prolific_session_id
    assert record["task"]["id"] == task.id

    assert record["event"] == %{
             "id" => Repo.get_by!(ParticipantEvent, event_id: event_id).id,
             "participation_id" => participation.id,
             "task_id" => task.id,
             "question_key" => "test-comparison.v1",
             "kind" => "question_exposure",
             "event_id" => event_id,
             "client_session_id" => client_session_id,
             "sequence" => 7,
             "client_elapsed_ms" => 1_250,
             "duration_ms" => 400,
             "client_occurred_at" => DateTime.to_iso8601(occurred_at),
             "server_received_at" => DateTime.to_iso8601(received_at),
             "metadata" => %{"reason" => "question_changed"},
             "inserted_at" => DateTime.to_iso8601(received_at)
           }
  end

  test "filters by condition and deterministically orders events without tasks" do
    included_condition = condition_fixture()
    excluded_condition = condition_fixture()
    run_fixture(included_condition)
    run_fixture(excluded_condition)

    assert {:ok, included} = assign(included_condition)
    assert {:ok, excluded} = assign(excluded_condition)

    received_at = ~U[2026-08-14 08:00:00.000000Z]
    session_id = Ecto.UUID.generate()

    insert_event(included,
      kind: :visibility_hidden,
      event_id: Ecto.UUID.generate(),
      client_session_id: session_id,
      sequence: 2,
      server_received_at: received_at
    )

    insert_event(included,
      kind: :visibility_visible,
      event_id: Ecto.UUID.generate(),
      client_session_id: session_id,
      sequence: 1,
      server_received_at: received_at
    )

    insert_event(excluded,
      kind: :visibility_hidden,
      event_id: Ecto.UUID.generate(),
      server_received_at: received_at
    )

    assert {:ok, lines} = collect_jsonl(condition_key: included_condition.key)
    records = Enum.map(lines, &Jason.decode!/1)

    assert Enum.map(records, & &1["event"]["sequence"]) == [1, 2]
    assert Enum.all?(records, &(&1["condition"]["key"] == included_condition.key))
    assert Enum.all?(records, &is_nil(&1["task"]))
  end

  defp assign(condition) do
    DataCollection.consent_and_assign_run(
      condition,
      participation_attrs(condition),
      "test-consent.v1"
    )
  end

  defp insert_event(participation, attrs) do
    defaults = [
      participant_id: participation.id,
      kind: :visibility_hidden,
      event_id: Ecto.UUID.generate(),
      server_received_at: DateTime.utc_now(),
      metadata: %{}
    ]

    values = defaults |> Keyword.merge(attrs) |> Map.new()
    values = Map.put_new(values, :inserted_at, values.server_received_at)

    %ParticipantEvent{
      participant_id: values.participant_id,
      server_received_at: values.server_received_at,
      inserted_at: values.inserted_at
    }
    |> ParticipantEvent.changeset(
      Map.drop(values, [:participant_id, :server_received_at, :inserted_at])
    )
    |> Repo.insert!()
  end

  defp collect_jsonl(opts) do
    case ParticipantEventExports.reduce_jsonl([], fn line, lines -> [line | lines] end, opts) do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end
end
