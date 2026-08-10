defmodule SocialCrowdWork.Repo.Migrations.CreateExperimentDataModel do
  use Ecto.Migration

  def change do
    create table(:conditions) do
      add :key, :string, null: false
      add :task_type, :string, null: false
      add :variants, :map, null: false, default: fragment("'{}'::jsonb")
      add :entry_token, :string, null: false
      add :prolific_study_id, :string
      add :prolific_completion_code, :string
      add :active, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:conditions, [:key])
    create unique_index(:conditions, [:entry_token])
    create constraint(:conditions, :conditions_key_not_blank, check: "btrim(key) <> ''")

    create constraint(:conditions, :conditions_entry_token_not_blank,
             check: "btrim(entry_token) <> ''"
           )

    create constraint(:conditions, :conditions_task_type_valid,
             check: "task_type IN ('comparison', 'binary_question')"
           )

    create constraint(:conditions, :conditions_variants_is_object,
             check: "jsonb_typeof(variants) = 'object'"
           )

    create table(:import_batches) do
      add :original_filename, :string, null: false
      add :source_sha256, :string, size: 64, null: false
      add :format_version, :string, null: false
      add :imported_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:import_batches, [:source_sha256])

    create constraint(:import_batches, :import_batches_filename_not_blank,
             check: "btrim(original_filename) <> ''"
           )

    create constraint(:import_batches, :import_batches_sha256_valid,
             check: "source_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:import_batches, :import_batches_format_version_not_blank,
             check: "btrim(format_version) <> ''"
           )

    create table(:runs) do
      add :condition_id, references(:conditions, on_delete: :nothing), null: false
      add :import_batch_id, references(:import_batches, on_delete: :nothing), null: false
      add :external_key, :string, null: false

      timestamps()
    end

    create index(:runs, [:condition_id])
    create index(:runs, [:import_batch_id])
    create unique_index(:runs, [:import_batch_id, :external_key])
    create constraint(:runs, :runs_external_key_not_blank, check: "btrim(external_key) <> ''")

    create table(:tasks) do
      add :run_id, references(:runs, on_delete: :delete_all), null: false
      add :position, :integer, null: false
      add :prompt_key, :string, null: false
      add :stimuli, :map, null: false

      timestamps()
    end

    create index(:tasks, [:run_id])
    create unique_index(:tasks, [:run_id, :position])
    create unique_index(:tasks, [:id, :run_id])
    create constraint(:tasks, :tasks_position_positive, check: "position > 0")
    create constraint(:tasks, :tasks_prompt_key_not_blank, check: "btrim(prompt_key) <> ''")
    create constraint(:tasks, :tasks_stimuli_is_object, check: "jsonb_typeof(stimuli) = 'object'")

    create table(:participations) do
      add :run_id, references(:runs, on_delete: :nothing), null: false
      add :prolific_participant_id, :string, null: false
      add :prolific_study_id, :string, null: false
      add :prolific_session_id, :string, null: false
      add :status, :string, null: false, default: "assigned"
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime

      timestamps()
    end

    create unique_index(:participations, [:run_id])
    create unique_index(:participations, [:prolific_session_id])
    create unique_index(:participations, [:id, :run_id])
    create index(:participations, [:prolific_participant_id, :prolific_study_id])

    create constraint(:participations, :participations_prolific_participant_id_not_blank,
             check: "btrim(prolific_participant_id) <> ''"
           )

    create constraint(:participations, :participations_prolific_study_id_not_blank,
             check: "btrim(prolific_study_id) <> ''"
           )

    create constraint(:participations, :participations_prolific_session_id_not_blank,
             check: "btrim(prolific_session_id) <> ''"
           )

    create constraint(:participations, :participations_status_valid,
             check: "status IN ('assigned', 'in_progress', 'completed')"
           )

    create constraint(:participations, :participations_completion_consistent,
             check:
               "(status = 'completed' AND completed_at IS NOT NULL) OR " <>
                 "(status <> 'completed' AND completed_at IS NULL)"
           )

    create table(:responses) do
      add :participation_id, references(:participations, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :nothing), null: false
      add :run_id, references(:runs, on_delete: :nothing), null: false
      add :choice, :string, null: false
      add :answered_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create index(:responses, [:task_id])
    create index(:responses, [:run_id])
    create unique_index(:responses, [:participation_id, :task_id])

    execute(
      """
      ALTER TABLE responses
      ADD CONSTRAINT responses_participation_run_fkey
      FOREIGN KEY (participation_id, run_id)
      REFERENCES participations(id, run_id)
      """,
      "ALTER TABLE responses DROP CONSTRAINT responses_participation_run_fkey"
    )

    execute(
      """
      ALTER TABLE responses
      ADD CONSTRAINT responses_task_run_fkey
      FOREIGN KEY (task_id, run_id)
      REFERENCES tasks(id, run_id)
      """,
      "ALTER TABLE responses DROP CONSTRAINT responses_task_run_fkey"
    )

    create constraint(:responses, :responses_choice_valid,
             check: "choice IN ('post_a', 'post_b', 'equal', 'yes', 'no', 'skip')"
           )
  end
end
