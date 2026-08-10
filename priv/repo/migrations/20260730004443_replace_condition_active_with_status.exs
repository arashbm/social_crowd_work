defmodule SocialCrowdWork.Repo.Migrations.ReplaceConditionActiveWithStatus do
  use Ecto.Migration

  def up do
    alter table(:conditions) do
      add :status, :string, null: false, default: "draft"
    end

    execute("UPDATE conditions SET status = 'active' WHERE active = true")

    alter table(:conditions) do
      remove :active
    end

    create constraint(:conditions, :conditions_status_valid,
             check: "status IN ('draft', 'active', 'paused', 'closed')"
           )
  end

  def down do
    drop constraint(:conditions, :conditions_status_valid)

    alter table(:conditions) do
      add :active, :boolean, null: false, default: false
    end

    execute("UPDATE conditions SET active = true WHERE status = 'active'")

    alter table(:conditions) do
      remove :status
    end
  end
end
