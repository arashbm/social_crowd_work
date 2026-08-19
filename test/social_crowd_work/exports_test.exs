defmodule SocialCrowdWork.ExportsTest do
  use SocialCrowdWork.DataCase, async: true

  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.DataCollection.Response
  alias SocialCrowdWork.Exports
  alias SocialCrowdWork.Repo

  import SocialCrowdWork.Fixtures

  test "exports every expected task question and preserves multiple responses" do
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

    first_task = %{first_task | questionnaire_key: "psychosocial-comparisons.v1"}
    run = run_fixture(condition, %{tasks: [first_task]})
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    [task] = run.tasks
    insert_response(participation, task, "worry.v1", :skip)
    insert_response(participation, task, "restlessness.v1", :post_a)

    assert {:ok, lines} = collect_jsonl(condition_key: condition.key)
    assert length(lines) == 3

    [answered, second_answered, unanswered] = Enum.map(lines, &Jason.decode!/1)
    assert answered["task"]["position"] == 1
    assert answered["task"]["questionnaire_key"] == "psychosocial-comparisons.v1"
    assert answered["questionnaire"] == %{"key" => "psychosocial-comparisons.v1"}
    assert answered["question"] == %{"key" => "worry.v1", "number" => 1}
    assert answered["response"]["choice"] == "skip"
    assert second_answered["question"] == %{"key" => "restlessness.v1", "number" => 2}
    assert second_answered["response"]["choice"] == "post_a"
    assert unanswered["question"] == %{"key" => "cognitive-disruption.v1", "number" => 3}
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
    condition = condition_fixture(:binary_question, %{instructions_key: "test-instructions.v1"})
    run = run_fixture(condition)
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    [task] = run.tasks
    response = insert_response(participation, task, "test-binary-question.v1", :yes)

    participation
    |> Ecto.Changeset.change(%{
      status: :completed,
      completed_at: response.answered_at,
      instruction_pages_completed: 1,
      instructions_completed_at: response.answered_at
    })
    |> Repo.update!()

    assert {:ok, [line]} = collect_jsonl(condition_key: condition.key)
    record = Jason.decode!(line)

    assert record["schema_version"] == "3"
    assert record["condition"]["task_type"] == "binary_question"
    assert record["condition"]["instructions_key"] == "test-instructions.v1"
    assert record["participation"]["status"] == "completed"
    assert record["participation"]["instructions_key"] == "test-instructions.v1"
    assert record["participation"]["instruction_pages_completed"] == 1
    assert record["participation"]["instructions_completed_at"]
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

  defp insert_response(participation, task, question_key, choice) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %Response{}
    |> Response.changeset(
      %{
        participation_id: participation.id,
        task_id: task.id,
        run_id: participation.run_id,
        question_key: question_key,
        choice: choice,
        answered_at: now
      },
      participation.run.condition.task_type
    )
    |> Repo.insert!()
  end
end
