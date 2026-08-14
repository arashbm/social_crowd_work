defmodule SocialCrowdWork.ParticipantEvents do
  @moduledoc """
  Validates and persists append-only participant telemetry.

  `ingest/2` accepts at most 25 client events. Participant identity and receipt
  timestamps are always supplied by the server, never by event payloads.
  """

  import Ecto.Changeset

  alias SocialCrowdWork.DataCollection.{ParticipantEvent, Participation}
  alias SocialCrowdWork.Experiments.Task
  alias SocialCrowdWork.Questionnaires
  alias SocialCrowdWork.Repo

  @max_batch_size 25
  @client_kinds ParticipantEvent.kinds() -- [:answer_created, :answer_changed]
  @payload_fields ~w(event_id task_id question_key kind client_session_id sequence client_elapsed_ms duration_ms client_occurred_at metadata)
  @question_kinds [:question_rendered, :question_exposure, :copy]
  @empty_metadata_kinds [
    :task_rendered,
    :question_rendered,
    :visibility_hidden,
    :visibility_visible,
    :window_blurred,
    :window_focused
  ]
  @context_metadata_keys ~w(device_class viewport_bucket touch_capable browser_family browser_major os_family)
  @exposure_reasons ~w(question_changed task_changed visibility_hidden window_blurred page_unloaded)
  @copy_targets ~w(question post post_a post_b other)

  def ingest_batch(%Participation{} = participant, events), do: ingest(participant, events)

  def ingest(%Participation{id: participant_id}, events) when is_list(events) do
    with :ok <- validate_batch_size(events),
         %Participation{} = participant <- Repo.get(Participation, participant_id),
         received_at <- now(),
         {:ok, rows} <- validate_events(events, participant, received_at) do
      {inserted, _rows} =
        Repo.insert_all(ParticipantEvent, rows,
          on_conflict: :nothing,
          conflict_target: [:event_id]
        )

      {:ok,
       %{
         accepted_ids: Enum.map(rows, & &1.event_id),
         accepted: length(rows),
         inserted: inserted
       }}
    else
      nil -> {:error, :participation_not_found}
      {:error, _reason} = error -> error
    end
  end

  def ingest(%Participation{}, _events), do: {:error, :invalid_batch}

  @doc false
  def insert_answer_event!(participant, task, question_key, previous_choice, new_choice) do
    kind = if is_nil(previous_choice), do: :answer_created, else: :answer_changed
    received_at = now()

    attrs = %{
      participant_id: participant.id,
      task_id: task.id,
      question_key: question_key,
      kind: kind,
      event_id: Ecto.UUID.generate(),
      server_received_at: received_at,
      inserted_at: received_at,
      metadata: %{
        "previous_choice" => choice_value(previous_choice),
        "new_choice" => choice_value(new_choice)
      }
    }

    %ParticipantEvent{
      participant_id: participant.id,
      server_received_at: received_at,
      inserted_at: received_at
    }
    |> ParticipantEvent.changeset(attrs)
    |> validate_answer_metadata(kind)
    |> Repo.insert!()
  end

  defp validate_batch_size(events) when length(events) <= @max_batch_size, do: :ok
  defp validate_batch_size(_events), do: {:error, :batch_too_large}

  defp validate_events(events, participant, received_at) do
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {payload, index}, {:ok, rows} ->
      case validate_event(payload, participant, received_at) do
        {:ok, row} -> {:cont, {:ok, [row | rows]}}
        {:error, reason} -> {:halt, {:error, {:invalid_event, index, reason}}}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp validate_event(payload, participant, received_at) when is_map(payload) do
    with :ok <- reject_unknown_fields(payload),
         attrs <- client_attrs(payload),
         event <- %ParticipantEvent{
           participant_id: participant.id,
           server_received_at: received_at,
           inserted_at: received_at
         },
         changeset <- ParticipantEvent.changeset(event, attrs),
         changeset <- validate_client_kind(changeset),
         changeset <- validate_identity(changeset, participant),
         changeset <- validate_metadata(changeset) do
      event_row(changeset)
    else
      {:error, _reason} = error -> error
    end
  end

  defp validate_event(_payload, _participant, _received_at), do: {:error, :not_an_object}

  defp reject_unknown_fields(payload) do
    unknown = payload |> Map.keys() |> Enum.map(&to_string/1) |> Kernel.--(@payload_fields)
    if unknown == [], do: :ok, else: {:error, {:unknown_fields, Enum.sort(unknown)}}
  end

  defp client_attrs(payload) do
    payload
    |> Map.take(@payload_fields ++ Enum.map(@payload_fields, &String.to_existing_atom/1))
    |> Map.new(fn {key, value} -> {key |> to_string() |> String.to_existing_atom(), value} end)
  end

  defp event_row(%{valid?: false} = changeset), do: {:error, changeset_errors(changeset)}

  defp event_row(changeset) do
    event = apply_changes(changeset)

    {:ok,
     event
     |> Map.from_struct()
     |> Map.take([
       :participant_id,
       :task_id,
       :question_key,
       :kind,
       :event_id,
       :client_session_id,
       :sequence,
       :client_elapsed_ms,
       :duration_ms,
       :client_occurred_at,
       :server_received_at,
       :metadata,
       :inserted_at
     ])}
  end

  defp validate_client_kind(changeset) do
    validate_inclusion(changeset, :kind, @client_kinds)
  end

  defp validate_identity(changeset, participant) do
    kind = get_field(changeset, :kind)
    task_id = get_field(changeset, :task_id)
    question_key = get_field(changeset, :question_key)

    changeset =
      cond do
        kind == :task_rendered and is_nil(task_id) ->
          add_error(changeset, :task_id, "is required")

        kind in @question_kinds and is_nil(task_id) ->
          add_error(changeset, :task_id, "is required")

        true ->
          changeset
      end

    changeset =
      if kind in @question_kinds and is_nil(question_key),
        do: add_error(changeset, :question_key, "is required"),
        else: changeset

    case task_id && Repo.get(Task, task_id) do
      nil when is_nil(task_id) ->
        if question_key,
          do: add_error(changeset, :question_key, "requires a task"),
          else: changeset

      nil ->
        add_error(changeset, :task_id, "does not exist")

      %Task{run_id: run_id} when run_id != participant.run_id ->
        add_error(changeset, :task_id, "does not belong to the participation run")

      task ->
        validate_question(changeset, task, question_key)
    end
  end

  defp validate_question(changeset, _task, nil), do: changeset

  defp validate_question(changeset, task, question_key) do
    case Questionnaires.fetch(task.questionnaire_key) do
      {:ok, questionnaire} ->
        if Enum.any?(questionnaire.questions(), &(&1.key() == question_key)),
          do: changeset,
          else: add_error(changeset, :question_key, "does not belong to the task questionnaire")

      :error ->
        add_error(changeset, :task_id, "has an unknown questionnaire")
    end
  end

  defp validate_metadata(changeset) do
    kind = get_field(changeset, :kind)
    metadata = get_field(changeset, :metadata)

    cond do
      not is_map(metadata) -> changeset
      kind in @empty_metadata_kinds -> validate_empty_metadata(changeset, metadata)
      kind == :client_context -> validate_context_metadata(changeset, metadata)
      kind == :question_exposure -> validate_exposure_metadata(changeset, metadata)
      kind == :copy -> validate_enum_metadata(changeset, metadata, "target", @copy_targets)
      true -> changeset
    end
  end

  defp validate_empty_metadata(changeset, metadata) do
    if map_size(metadata) == 0,
      do: changeset,
      else: add_error(changeset, :metadata, "must be empty for this event kind")
  end

  defp validate_context_metadata(changeset, metadata) do
    valid? =
      Enum.sort(Map.keys(metadata)) == Enum.sort(@context_metadata_keys) and
        metadata["device_class"] in ~w(mobile tablet desktop) and
        metadata["viewport_bucket"] in ~w(small medium large) and
        is_boolean(metadata["touch_capable"]) and
        metadata["browser_family"] in ~w(edge firefox chrome safari other) and
        (is_nil(metadata["browser_major"]) or
           valid_metadata_value?(metadata["browser_major"], {:integer, 1_000})) and
        metadata["os_family"] in ~w(android ios windows macos linux other)

    if valid?,
      do: changeset,
      else: add_error(changeset, :metadata, "is invalid for client_context")
  end

  defp validate_exposure_metadata(changeset, metadata) do
    valid? =
      Enum.sort(Map.keys(metadata)) == ~w(focused_ms reason visible_ms) and
        metadata["reason"] in @exposure_reasons and
        valid_metadata_value?(metadata["visible_ms"], {:integer, 604_800_000}) and
        valid_metadata_value?(metadata["focused_ms"], {:integer, 604_800_000}) and
        metadata["focused_ms"] <= metadata["visible_ms"] and
        is_integer(get_field(changeset, :duration_ms)) and
        metadata["visible_ms"] <= get_field(changeset, :duration_ms)

    if valid?,
      do: changeset,
      else: add_error(changeset, :metadata, "is invalid for question_exposure")
  end

  defp validate_enum_metadata(changeset, metadata, key, allowed) do
    if Map.keys(metadata) == [key] and Map.get(metadata, key) in allowed,
      do: changeset,
      else: add_error(changeset, :metadata, "must contain only #{key} with an allowed value")
  end

  defp validate_answer_metadata(changeset, :answer_created) do
    metadata = get_field(changeset, :metadata)

    if metadata["previous_choice"] == nil and is_binary(metadata["new_choice"]),
      do: changeset,
      else: add_error(changeset, :metadata, "is invalid for answer_created")
  end

  defp validate_answer_metadata(changeset, :answer_changed) do
    metadata = get_field(changeset, :metadata)

    if is_binary(metadata["previous_choice"]) and is_binary(metadata["new_choice"]) and
         metadata["previous_choice"] != metadata["new_choice"],
       do: changeset,
       else: add_error(changeset, :metadata, "is invalid for answer_changed")
  end

  defp valid_metadata_value?(value, {:integer, max}), do: is_integer(value) and value in 0..max

  defp changeset_errors(changeset) do
    traverse_errors(changeset, fn {message, options} ->
      Enum.reduce(options, message, fn {key, value}, rendered ->
        String.replace(rendered, "%{#{key}}", inspect(value))
      end)
    end)
  end

  defp choice_value(nil), do: nil
  defp choice_value(choice), do: Atom.to_string(choice)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
