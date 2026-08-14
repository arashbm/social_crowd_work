defmodule SocialCrowdWork.Repo.Migrations.CreateParticipantEvents do
  use Ecto.Migration

  def up do
    create table(:participant_events) do
      add :participant_id, references(:participations, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :restrict)
      add :question_key, :string
      add :kind, :string, null: false
      add :event_id, :uuid, null: false
      add :client_session_id, :uuid
      add :sequence, :bigint
      add :client_elapsed_ms, :bigint
      add :duration_ms, :bigint
      add :client_occurred_at, :utc_datetime_usec
      add :server_received_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:participant_events, [:event_id])
    create index(:participant_events, [:participant_id, :server_received_at])

    create index(:participant_events, [:participant_id, :task_id, :question_key, :kind],
             name: :participant_events_scope_index
           )

    create index(:participant_events, [:participant_id, :client_session_id, :sequence],
             name: :participant_events_client_sequence_index
           )

    create index(:participant_events, [:task_id])

    create constraint(:participant_events, :participant_events_kind_valid,
             check:
               "kind IN ('client_context', 'task_rendered', 'question_rendered', " <>
                 "'question_exposure', 'visibility_hidden', 'visibility_visible', " <>
                 "'window_blurred', 'window_focused', 'copy', 'answer_created', " <>
                 "'answer_changed')"
           )

    create constraint(:participant_events, :participant_events_question_key_not_blank,
             check: "question_key IS NULL OR btrim(question_key) <> ''"
           )

    create constraint(:participant_events, :participant_events_sequence_valid,
             check: "sequence IS NULL OR sequence BETWEEN 0 AND 9007199254740991"
           )

    for column <- [:client_elapsed_ms, :duration_ms] do
      create constraint(:participant_events, "participant_events_#{column}_valid",
               check: "#{column} IS NULL OR #{column} BETWEEN 0 AND 604800000"
             )
    end

    create constraint(:participant_events, :participant_events_metadata_is_object,
             check: "jsonb_typeof(metadata) = 'object'"
           )
  end

  def down do
    drop table(:participant_events)
  end
end
