defmodule SocialCrowdWork.Repo.Migrations.CreateAdminAuditEvents do
  use Ecto.Migration

  def change do
    create table(:admin_audit_events) do
      add :admin_id, references(:admins, on_delete: :nothing), null: false
      add :action, :string, null: false
      add :target_type, :string
      add :target_id, :bigint
      add :metadata, :map, null: false, default: fragment("'{}'::jsonb")

      timestamps(updated_at: false)
    end

    create index(:admin_audit_events, [:admin_id])
    create index(:admin_audit_events, [:inserted_at])
    create index(:admin_audit_events, [:target_type, :target_id])

    create constraint(:admin_audit_events, :admin_audit_events_action_not_blank,
             check: "btrim(action) <> ''"
           )

    create constraint(:admin_audit_events, :admin_audit_events_metadata_is_object,
             check: "jsonb_typeof(metadata) = 'object'"
           )
  end
end
