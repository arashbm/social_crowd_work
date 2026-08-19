defmodule SocialCrowdWork.InstructionSchemaTest do
  use SocialCrowdWork.DataCase, async: true

  alias SocialCrowdWork.DataCollection.Participation
  alias SocialCrowdWork.Experiments
  alias SocialCrowdWork.Experiments.Condition

  import SocialCrowdWork.Fixtures

  test "condition design accepts only known instruction set keys" do
    base_attrs = %{
      key: "instruction-condition-#{System.unique_integer([:positive])}",
      task_type: :comparison,
      variants: %{},
      entry_token: "entry-token"
    }

    assert Condition.changeset(%Condition{}, Map.put(base_attrs, :instructions_key, "unknown.v1"))
           |> errors_on()
           |> Map.fetch!(:instructions_key) == ["is not a known instruction set"]

    assert Condition.changeset(
             %Condition{},
             Map.put(base_attrs, :instructions_key, "test-instructions.v1")
           ).valid?
  end

  test "operational configuration cannot mutate imported design fields" do
    condition = condition_fixture(:comparison, %{instructions_key: "test-instructions.v1"})

    assert {:ok, configured} =
             Experiments.configure_condition(condition, %{
               key: "changed",
               task_type: :binary_question,
               variants: %{"changed" => true},
               instructions_key: nil,
               status: :paused
             })

    assert configured.key == condition.key
    assert configured.task_type == condition.task_type
    assert configured.variants == condition.variants
    assert configured.instructions_key == "test-instructions.v1"
    assert configured.status == :paused
  end

  test "participation instruction progress is nonnegative and requires a snapshot key" do
    attrs = %{
      run_id: 1,
      prolific_participant_id: "participant",
      prolific_study_id: "study",
      prolific_session_id: "session",
      consent_key: "consent.v1",
      consented_at: ~U[2026-08-19 10:00:00Z],
      status: :assigned,
      started_at: ~U[2026-08-19 10:00:00Z]
    }

    assert Participation.changeset(
             %Participation{},
             Map.put(attrs, :instruction_pages_completed, -1)
           )
           |> errors_on()
           |> Map.fetch!(:instruction_pages_completed) ==
             ["must be greater than or equal to 0"]

    assert Participation.changeset(
             %Participation{},
             Map.merge(attrs, %{
               instruction_pages_completed: 1,
               instructions_completed_at: ~U[2026-08-19 10:01:00Z]
             })
           )
           |> errors_on()
           |> Map.fetch!(:instructions_key) ==
             ["must be set when instruction progress exists"]

    assert Participation.changeset(
             %Participation{},
             Map.merge(attrs, %{
               instructions_key: "retired-instructions.v1",
               instruction_pages_completed: 1,
               instructions_completed_at: ~U[2026-08-19 10:01:00Z]
             })
           ).valid?
  end
end
