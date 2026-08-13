defmodule SocialCrowdWork.Exports do
  @moduledoc """
  Streams analysis-ready task records as newline-delimited JSON.

  Every assigned task is exported, including tasks without a response. This
  preserves the distinction between missing data and an explicit `skip` choice.
  """

  import Ecto.Query

  alias SocialCrowdWork.DataCollection.{Participation, Response}
  alias SocialCrowdWork.Experiments.{Condition, ImportBatch, Run, Task}
  alias SocialCrowdWork.Questionnaires
  alias SocialCrowdWork.Repo

  @schema_version "2"

  def reduce_jsonl(initial_accumulator, reducer, opts \\ []) when is_function(reducer, 2) do
    query = export_query(opts)

    Repo.transaction(
      fn ->
        query
        |> Repo.stream(max_rows: 500)
        |> Stream.chunk_by(fn {_, _, _, task, participation, _} ->
          {participation.id, task.id}
        end)
        |> Enum.reduce(initial_accumulator, fn rows, accumulator ->
          reduce_task_rows(rows, accumulator, reducer)
        end)
      end,
      timeout: :infinity
    )
  end

  defp export_query(opts) do
    from(participation in Participation,
      join: run in Run,
      on: run.id == participation.run_id,
      join: condition in Condition,
      on: condition.id == run.condition_id,
      join: import_batch in ImportBatch,
      on: import_batch.id == run.import_batch_id,
      join: task in Task,
      on: task.run_id == run.id,
      left_join: response in Response,
      on:
        response.participation_id == participation.id and
          response.task_id == task.id,
      order_by: [
        asc: condition.key,
        asc: run.external_key,
        asc: participation.id,
        asc: task.position,
        asc: response.question_key
      ],
      select: {condition, import_batch, run, task, participation, response}
    )
    |> maybe_filter_condition(Keyword.get(opts, :condition_key))
  end

  defp maybe_filter_condition(query, nil), do: query

  defp maybe_filter_condition(query, condition_key) do
    where(query, [participation, run, condition], condition.key == ^condition_key)
  end

  defp reduce_task_rows(rows, accumulator, reducer) do
    [{condition, import_batch, run, task, participation, _} | _] = rows

    responses =
      rows
      |> Enum.map(&elem(&1, 5))
      |> Enum.reject(&is_nil/1)
      |> Map.new(&{&1.question_key, &1})

    questionnaire = Questionnaires.fetch!(task.questionnaire_key)

    questionnaire.questions()
    |> Enum.with_index(1)
    |> Enum.reduce(accumulator, fn {question, number}, acc ->
      row = {condition, import_batch, run, task, participation, question, number}
      reducer.(encode_row(row, Map.get(responses, question.key())), acc)
    end)
  end

  defp encode_row(
         {condition, import_batch, run, task, participation, question, question_number},
         response
       ) do
    %{
      schema_version: @schema_version,
      condition: %{
        id: condition.id,
        key: condition.key,
        task_type: condition.task_type,
        variants: condition.variants
      },
      import_batch: %{
        id: import_batch.id,
        filename: import_batch.original_filename,
        source_sha256: import_batch.source_sha256,
        format_version: import_batch.format_version,
        imported_at: timestamp(import_batch.imported_at)
      },
      run: %{
        id: run.id,
        key: run.external_key
      },
      task: %{
        id: task.id,
        position: task.position,
        questionnaire_key: task.questionnaire_key,
        stimuli: task.stimuli
      },
      questionnaire: %{key: task.questionnaire_key},
      question: %{key: question.key(), number: question_number},
      participation: %{
        id: participation.id,
        prolific_participant_id: participation.prolific_participant_id,
        prolific_study_id: participation.prolific_study_id,
        prolific_session_id: participation.prolific_session_id,
        status: participation.status,
        consent_key: participation.consent_key,
        consented_at: timestamp(participation.consented_at),
        started_at: timestamp(participation.started_at),
        completed_at: timestamp(participation.completed_at)
      },
      response: response_data(response)
    }
    |> Jason.encode!()
    |> Kernel.<>("\n")
  end

  defp response_data(nil), do: nil

  defp response_data(response) do
    %{
      id: response.id,
      choice: response.choice,
      first_answered_at: timestamp(response.inserted_at),
      answered_at: timestamp(response.answered_at)
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(value), do: DateTime.to_iso8601(value)
end
