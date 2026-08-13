defmodule SocialCrowdWork.Repo.Migrations.CreateParticipantLaunches do
  use Ecto.Migration

  def change do
    create table(:participant_launches) do
      add :token_hash, :binary, null: false
      add :condition_id, references(:conditions, on_delete: :restrict), null: false
      add :participation_id, references(:participations, on_delete: :delete_all)
      add :prolific_participant_id, :string, null: false
      add :prolific_study_id, :string, null: false
      add :prolific_session_id, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:participant_launches, [:token_hash])
    create index(:participant_launches, [:expires_at])
    create index(:participant_launches, [:condition_id])
    create index(:participant_launches, [:participation_id])
    create index(:participant_launches, [:prolific_session_id])

    create constraint(:participant_launches, :participant_launches_token_hash_length,
             check: "octet_length(token_hash) = 32"
           )

    for field <- [:prolific_participant_id, :prolific_study_id, :prolific_session_id] do
      create constraint(
               :participant_launches,
               "participant_launches_#{field}_not_blank",
               check: "btrim(#{field}) <> ''"
             )
    end

    create constraint(:participant_launches, :participant_launches_expiry_after_insert,
             check: "expires_at > inserted_at"
           )
  end
end
