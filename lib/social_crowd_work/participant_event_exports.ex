defmodule SocialCrowdWork.ParticipantEventExports do
  @moduledoc """
  Streams raw participant telemetry events as newline-delimited JSON.

  Each line represents one event without deriving metrics or calculations.
  """

  import Ecto.Query

  alias SocialCrowdWork.DataCollection.{ParticipantEvent, Participation}
  alias SocialCrowdWork.Experiments.{Condition, Run, Task}
  alias SocialCrowdWork.Repo

  @schema_version "2"

  def reduce_jsonl(initial_accumulator, reducer, opts \\ []) when is_function(reducer, 2) do
    query = export_query(opts)

    Repo.transaction(
      fn ->
        query
        |> Repo.stream(max_rows: 500)
        |> Enum.reduce(initial_accumulator, fn row, accumulator ->
          reducer.(encode_row(row), accumulator)
        end)
      end,
      timeout: :infinity
    )
  end

  defp export_query(opts) do
    from(event in ParticipantEvent,
      join: participation in Participation,
      on: participation.id == event.participant_id,
      join: run in Run,
      on: run.id == participation.run_id,
      join: condition in Condition,
      on: condition.id == run.condition_id,
      left_join: task in Task,
      on: task.id == event.task_id,
      order_by: [
        asc: condition.key,
        asc: run.external_key,
        asc: participation.id,
        asc: event.server_received_at,
        asc: event.client_session_id,
        asc: event.sequence,
        asc: event.id
      ],
      select: {
        condition,
        run,
        participation,
        task,
        event
      }
    )
    |> maybe_filter_condition(Keyword.get(opts, :condition_key))
  end

  defp maybe_filter_condition(query, nil), do: query

  defp maybe_filter_condition(query, condition_key) do
    where(query, [_event, _participation, _run, condition], condition.key == ^condition_key)
  end

  defp encode_row({condition, run, participation, task, event}) do
    %{
      schema_version: @schema_version,
      condition: %{
        id: condition.id,
        key: condition.key,
        task_type: condition.task_type,
        variants: condition.variants,
        instructions_key: condition.instructions_key
      },
      run: %{
        id: run.id,
        key: run.external_key
      },
      participation: %{
        id: participation.id,
        prolific_participant_id: participation.prolific_participant_id,
        prolific_study_id: participation.prolific_study_id,
        prolific_session_id: participation.prolific_session_id,
        status: participation.status,
        instructions_key: participation.instructions_key,
        instruction_pages_completed: participation.instruction_pages_completed,
        instructions_completed_at: timestamp(participation.instructions_completed_at)
      },
      task: task_data(task),
      event: %{
        id: event.id,
        participation_id: event.participant_id,
        task_id: event.task_id,
        question_key: event.question_key,
        kind: event.kind,
        event_id: event.event_id,
        client_session_id: event.client_session_id,
        sequence: event.sequence,
        client_elapsed_ms: event.client_elapsed_ms,
        duration_ms: event.duration_ms,
        client_occurred_at: timestamp(event.client_occurred_at),
        server_received_at: timestamp(event.server_received_at),
        metadata: event.metadata,
        inserted_at: timestamp(event.inserted_at)
      }
    }
    |> Jason.encode!()
    |> Kernel.<>("\n")
  end

  defp task_data(nil), do: nil

  defp task_data(task) do
    %{
      id: task.id,
      position: task.position,
      questionnaire_key: task.questionnaire_key
    }
  end

  defp timestamp(nil), do: nil
  defp timestamp(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp timestamp(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
end
