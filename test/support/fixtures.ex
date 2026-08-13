defmodule SocialCrowdWork.Fixtures do
  alias SocialCrowdWork.Experiments

  def condition_fixture(task_type \\ :comparison, attrs \\ %{}) do
    unique = unique_string()

    defaults = %{
      key: "condition-#{unique}",
      task_type: task_type,
      variants: %{"language" => "en"},
      prolific_study_id: "study-#{unique}",
      prolific_completion_code: "COMPLETE#{unique}",
      consent_key: "test-consent.v1",
      status: :active
    }

    {:ok, condition} = Experiments.create_condition(Map.merge(defaults, attrs))
    condition
  end

  def import_batch_fixture(attrs \\ %{}) do
    unique = unique_string()

    defaults = %{
      original_filename: "batch-#{unique}.json",
      source_sha256: sha256(unique),
      format_version: "2"
    }

    {:ok, import_batch} = Experiments.create_import_batch(Map.merge(defaults, attrs))
    import_batch
  end

  def run_fixture(condition, attrs \\ %{}) do
    import_batch = Map.get(attrs, :import_batch, import_batch_fixture())
    tasks = Map.get(attrs, :tasks, default_tasks(condition.task_type))

    run_attrs = %{
      import_batch_id: import_batch.id,
      external_key: Map.get(attrs, :external_key, "run-#{unique_string()}"),
      tasks: tasks
    }

    {:ok, run} = Experiments.create_run_with_tasks(condition, run_attrs)
    run
  end

  def participation_attrs(condition, attrs \\ %{}) do
    unique = unique_string()

    defaults = %{
      prolific_participant_id: "participant-#{unique}",
      prolific_study_id: condition.prolific_study_id,
      prolific_session_id: "session-#{unique}"
    }

    Map.merge(defaults, attrs)
  end

  def comparison_task(position \\ 1) do
    %{
      position: position,
      questionnaire_key: "test-comparison.v1",
      stimuli: %{
        "post_a" => %{"text" => "First post"},
        "post_b" => %{"text" => "Second post"}
      }
    }
  end

  def binary_question_task(position \\ 1) do
    %{
      position: position,
      questionnaire_key: "test-binary-question.v1",
      stimuli: %{"post" => %{"text" => "The post"}}
    }
  end

  defp default_tasks(:comparison), do: [comparison_task()]
  defp default_tasks(:binary_question), do: [binary_question_task()]

  defp sha256(value) do
    :sha256
    |> :crypto.hash(value)
    |> Base.encode16(case: :lower)
  end

  defp unique_string do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
end
