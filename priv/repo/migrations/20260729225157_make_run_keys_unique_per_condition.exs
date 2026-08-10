defmodule SocialCrowdWork.Repo.Migrations.MakeRunKeysUniquePerCondition do
  use Ecto.Migration

  def change do
    drop unique_index(:runs, [:import_batch_id, :external_key])
    create unique_index(:runs, [:condition_id, :external_key])
  end
end
