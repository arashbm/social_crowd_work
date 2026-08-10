defmodule SocialCrowdWork.Repo.Migrations.AddVersionedConsent do
  use Ecto.Migration

  def up do
    alter table(:conditions) do
      add :consent_key, :string
    end

    alter table(:participations) do
      add :consent_key, :string
      add :consented_at, :utc_datetime
    end

    execute("""
    UPDATE participations
    SET consent_key = 'legacy-unversioned.v0', consented_at = started_at
    WHERE consent_key IS NULL
    """)

    alter table(:participations) do
      modify :consent_key, :string, null: false
      modify :consented_at, :utc_datetime, null: false
    end

    create constraint(:conditions, :conditions_consent_key_not_blank,
             check: "consent_key IS NULL OR btrim(consent_key) <> ''"
           )

    create constraint(:participations, :participations_consent_key_not_blank,
             check: "btrim(consent_key) <> ''"
           )
  end

  def down do
    drop constraint(:participations, :participations_consent_key_not_blank)
    drop constraint(:conditions, :conditions_consent_key_not_blank)

    alter table(:participations) do
      remove :consented_at
      remove :consent_key
    end

    alter table(:conditions) do
      remove :consent_key
    end
  end
end
