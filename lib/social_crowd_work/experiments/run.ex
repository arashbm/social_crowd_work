defmodule SocialCrowdWork.Experiments.Run do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.DataCollection.Participation
  alias SocialCrowdWork.Experiments.{Condition, ImportBatch, Task}

  schema "runs" do
    field :external_key, :string

    belongs_to :condition, Condition
    belongs_to :import_batch, ImportBatch
    has_many :tasks, Task
    has_one :participation, Participation

    timestamps(type: :utc_datetime)
  end

  def changeset(run, attrs) do
    run
    |> cast(attrs, [:condition_id, :import_batch_id, :external_key])
    |> validate_required([:condition_id, :import_batch_id, :external_key])
    |> validate_length(:external_key, min: 1, max: 255)
    |> foreign_key_constraint(:condition_id)
    |> foreign_key_constraint(:import_batch_id)
    |> unique_constraint(:external_key, name: :runs_condition_id_external_key_index)
    |> check_constraint(:external_key, name: :runs_external_key_not_blank)
  end
end
