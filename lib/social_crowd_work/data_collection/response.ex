defmodule SocialCrowdWork.DataCollection.Response do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.DataCollection.Participation
  alias SocialCrowdWork.Experiments.{Run, Task}

  @choices [:post_a, :post_b, :equal, :yes, :no, :skip]
  @choices_by_task_type %{
    comparison: [:post_a, :post_b, :equal, :skip],
    binary_question: [:yes, :no, :skip]
  }

  schema "responses" do
    field :choice, Ecto.Enum, values: @choices
    field :answered_at, :utc_datetime

    belongs_to :participation, Participation
    belongs_to :task, Task
    belongs_to :run, Run

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(response, attrs, task_type) do
    allowed_choices = Map.get(@choices_by_task_type, task_type, [])

    response
    |> cast(attrs, [:participation_id, :task_id, :run_id, :choice, :answered_at])
    |> validate_required([:participation_id, :task_id, :run_id, :choice, :answered_at])
    |> validate_inclusion(:choice, allowed_choices)
    |> foreign_key_constraint(:participation_id)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:run_id)
    |> foreign_key_constraint(:participation_id, name: :responses_participation_run_fkey)
    |> foreign_key_constraint(:task_id, name: :responses_task_run_fkey)
    |> unique_constraint(:task_id, name: :responses_participation_id_task_id_index)
    |> check_constraint(:choice, name: :responses_choice_valid)
  end

  def choices, do: @choices
  def choices_for(task_type), do: Map.get(@choices_by_task_type, task_type, [])
end
