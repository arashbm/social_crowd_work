defmodule SocialCrowdWork.ExportsTest do
  use SocialCrowdWork.DataCase, async: true

  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.Exports

  import SocialCrowdWork.Fixtures

  test "exports every assigned task and distinguishes skip from no response" do
    condition = condition_fixture()

    first_task =
      comparison_task(1)
      |> put_in(
        [:stimuli, "post_a"],
        %{
          "text" => "Nested post",
          "author" => %{"handle" => "person.example"},
          "scores" => [0.2, 0.8]
        }
      )

    run = run_fixture(condition, %{tasks: [first_task, comparison_task(2)]})
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    task = Enum.find(run.tasks, &(&1.position == 1))
    assert {:ok, _response} = DataCollection.record_response(participation, task.id, :skip)

    assert {:ok, lines} = collect_jsonl(condition_key: condition.key)
    assert length(lines) == 2

    [answered, unanswered] = Enum.map(lines, &Jason.decode!/1)
    assert answered["task"]["position"] == 1
    assert answered["response"]["choice"] == "skip"
    assert unanswered["task"]["position"] == 2
    assert unanswered["response"] == nil

    assert answered["task"]["stimuli"]["post_a"]["author"] == %{
             "handle" => "person.example"
           }

    assert answered["task"]["stimuli"]["post_a"]["scores"] == [0.2, 0.8]
    assert answered["participation"]["prolific_participant_id"] == attrs.prolific_participant_id
    assert answered["participation"]["prolific_study_id"] == attrs.prolific_study_id
    assert answered["participation"]["prolific_session_id"] == attrs.prolific_session_id
    assert answered["participation"]["consent_key"] == "test-consent.v1"
    assert answered["participation"]["consented_at"]
    assert answered["import_batch"]["source_sha256"]
  end

  test "exports completed participation and response timestamps" do
    condition = condition_fixture(:binary_question)
    run = run_fixture(condition)
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    [task] = run.tasks
    assert {:ok, _response} = DataCollection.record_response(participation, task.id, :yes)
    assert {:ok, _completed} = DataCollection.complete_participation(participation)

    assert {:ok, [line]} = collect_jsonl(condition_key: condition.key)
    record = Jason.decode!(line)

    assert record["schema_version"] == "1"
    assert record["condition"]["task_type"] == "binary_question"
    assert record["participation"]["status"] == "completed"
    assert record["participation"]["completed_at"]
    assert record["response"]["choice"] == "yes"
    assert record["response"]["first_answered_at"]
    assert record["response"]["answered_at"]
  end

  test "filters exports by condition key and orders runs deterministically" do
    included_condition = condition_fixture()
    excluded_condition = condition_fixture()

    run_fixture(included_condition, %{external_key: "run-b"})
    run_fixture(included_condition, %{external_key: "run-a"})
    run_fixture(excluded_condition, %{external_key: "other-run"})

    assert {:ok, _participation} = assign(included_condition)
    assert {:ok, _participation} = assign(included_condition)
    assert {:ok, _participation} = assign(excluded_condition)

    assert {:ok, lines} = collect_jsonl(condition_key: included_condition.key)
    records = Enum.map(lines, &Jason.decode!/1)

    assert Enum.map(records, & &1["run"]["key"]) == ["run-a", "run-b"]
    assert Enum.all?(records, &(&1["condition"]["key"] == included_condition.key))
  end

  defp collect_jsonl(opts) do
    case Exports.reduce_jsonl([], fn line, lines -> [line | lines] end, opts) do
      {:ok, lines} -> {:ok, Enum.reverse(lines)}
      error -> error
    end
  end

  defp assign(condition) do
    DataCollection.consent_and_assign_run(
      condition,
      participation_attrs(condition),
      "test-consent.v1"
    )
  end
end
