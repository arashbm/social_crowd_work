defmodule SocialCrowdWork.Experiments.Task do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.DataCollection.Response
  alias SocialCrowdWork.Experiments.Run

  @comparison_roles MapSet.new(["post_a", "post_b"])
  @binary_question_roles MapSet.new(["post"])

  schema "tasks" do
    field :position, :integer
    field :questionnaire_key, :string
    field :stimuli, :map

    belongs_to :run, Run
    has_many :responses, Response

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs, task_type) do
    task
    |> cast(attrs, [:run_id, :position, :questionnaire_key, :stimuli])
    |> validate_required([:run_id, :position, :questionnaire_key, :stimuli])
    |> validate_number(:position, greater_than: 0)
    |> validate_length(:questionnaire_key, min: 1, max: 255)
    |> validate_stimuli(task_type)
    |> foreign_key_constraint(:run_id)
    |> unique_constraint(:position, name: :tasks_run_id_position_index)
    |> check_constraint(:position, name: :tasks_position_positive)
    |> check_constraint(:questionnaire_key, name: :tasks_questionnaire_key_not_blank)
    |> check_constraint(:stimuli, name: :tasks_stimuli_is_object)
  end

  def validate_stimuli(changeset, task_type) do
    validate_change(changeset, :stimuli, fn :stimuli, stimuli ->
      stimuli
      |> stimuli_errors(task_type)
      |> Enum.map(fn
        {"", message} -> {:stimuli, message}
        {path, message} -> {:stimuli, "#{path} #{message}"}
      end)
    end)
  end

  def stimuli_errors(stimuli, task_type) when is_map(stimuli) do
    expected_roles = expected_roles(task_type)
    actual_roles = stimuli |> Map.keys() |> MapSet.new()

    cond do
      is_nil(expected_roles) ->
        [{"", "has an unsupported task type"}]

      actual_roles != expected_roles ->
        [{"", "must contain exactly #{format_roles(expected_roles)}"}]

      true ->
        Enum.flat_map(stimuli, fn {role, post} -> validate_post(role, post) end)
    end
  end

  def stimuli_errors(_stimuli, _task_type), do: [{"", "must be an object"}]

  defp expected_roles(:comparison), do: @comparison_roles
  defp expected_roles(:binary_question), do: @binary_question_roles
  defp expected_roles(_task_type), do: nil

  defp validate_post(role, post) when is_map(post) do
    case Map.get(post, "text") do
      text when is_binary(text) ->
        if String.trim(text) == "" do
          [{"#{role}.text", "must not be blank"}]
        else
          []
        end

      _other ->
        [{"#{role}.text", "must be a string"}]
    end
  end

  defp validate_post(role, _post), do: [{role, "must be an object"}]

  defp format_roles(roles) do
    roles
    |> Enum.sort()
    |> Enum.join(" and ")
  end
end
