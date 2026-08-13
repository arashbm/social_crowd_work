defmodule SocialCrowdWork.Repo.Migrations.RedefineTasksForQuestionnaires do
  use Ecto.Migration

  def up do
    execute("""
    TRUNCATE TABLE responses, participations, tasks, runs, conditions, import_batches
    RESTART IDENTITY CASCADE
    """)

    drop constraint(:tasks, :tasks_prompt_key_not_blank)
    rename table(:tasks), :prompt_key, to: :questionnaire_key

    create constraint(:tasks, :tasks_questionnaire_key_not_blank,
             check: "btrim(questionnaire_key) <> ''"
           )

    drop index(:responses, [:participation_id, :task_id])

    alter table(:responses) do
      add :question_key, :string, null: false
    end

    create unique_index(:responses, [:participation_id, :task_id, :question_key])

    create constraint(:responses, :responses_question_key_not_blank,
             check: "btrim(question_key) <> ''"
           )
  end

  def down do
    execute("""
    TRUNCATE TABLE responses, participations, tasks, runs, conditions, import_batches
    RESTART IDENTITY CASCADE
    """)

    drop constraint(:responses, :responses_question_key_not_blank)
    drop index(:responses, [:participation_id, :task_id, :question_key])

    alter table(:responses) do
      remove :question_key
    end

    create unique_index(:responses, [:participation_id, :task_id])

    drop constraint(:tasks, :tasks_questionnaire_key_not_blank)
    rename table(:tasks), :questionnaire_key, to: :prompt_key

    create constraint(:tasks, :tasks_prompt_key_not_blank, check: "btrim(prompt_key) <> ''")
  end
end
