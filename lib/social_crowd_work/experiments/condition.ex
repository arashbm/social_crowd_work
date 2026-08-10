defmodule SocialCrowdWork.Experiments.Condition do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.Experiments.Run
  alias SocialCrowdWork.Consents

  @task_types [:comparison, :binary_question]
  @statuses [:draft, :active, :paused, :closed]

  schema "conditions" do
    field :key, :string
    field :task_type, Ecto.Enum, values: @task_types
    field :variants, :map, default: %{}
    field :entry_token, :string
    field :prolific_study_id, :string
    field :prolific_completion_code, :string
    field :consent_key, :string
    field :status, Ecto.Enum, values: @statuses, default: :draft

    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(condition, attrs) do
    condition
    |> cast(attrs, [
      :key,
      :task_type,
      :variants,
      :entry_token,
      :prolific_study_id,
      :prolific_completion_code,
      :consent_key,
      :status
    ])
    |> validate_required([:key, :task_type, :variants, :entry_token])
    |> validate_length(:key, min: 1, max: 255)
    |> validate_length(:entry_token, min: 1, max: 255)
    |> validate_variants()
    |> validate_consent_key()
    |> validate_active_configuration()
    |> unique_constraint(:key)
    |> unique_constraint(:entry_token)
    |> check_constraint(:key, name: :conditions_key_not_blank)
    |> check_constraint(:entry_token, name: :conditions_entry_token_not_blank)
    |> check_constraint(:consent_key, name: :conditions_consent_key_not_blank)
    |> check_constraint(:status, name: :conditions_status_valid)
    |> check_constraint(:task_type, name: :conditions_task_type_valid)
    |> check_constraint(:variants, name: :conditions_variants_is_object)
  end

  def task_types, do: @task_types
  def statuses, do: @statuses

  defp validate_variants(changeset) do
    validate_change(changeset, :variants, fn
      :variants, variants when is_map(variants) -> []
      :variants, _variants -> [variants: "must be an object"]
    end)
  end

  defp validate_consent_key(changeset) do
    validate_change(changeset, :consent_key, fn :consent_key, consent_key ->
      case Consents.fetch(consent_key) do
        {:ok, _consent} -> []
        :error -> [consent_key: "is not a known consent definition"]
      end
    end)
  end

  defp validate_active_configuration(changeset) do
    if get_field(changeset, :status) == :active do
      validate_required(changeset, [
        :prolific_study_id,
        :prolific_completion_code,
        :consent_key
      ])
    else
      changeset
    end
  end
end
