defmodule SocialCrowdWork.DataCollection.Participation do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.DataCollection.Response
  alias SocialCrowdWork.Experiments.Run

  @statuses [:assigned, :in_progress, :completed]

  schema "participations" do
    field :prolific_participant_id, :string
    field :prolific_study_id, :string
    field :prolific_session_id, :string
    field :consent_key, :string
    field :consented_at, :utc_datetime
    field :status, Ecto.Enum, values: @statuses, default: :assigned
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :run, Run
    has_many :responses, Response

    timestamps(type: :utc_datetime)
  end

  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [
      :run_id,
      :prolific_participant_id,
      :prolific_study_id,
      :prolific_session_id,
      :consent_key,
      :consented_at,
      :status,
      :started_at,
      :completed_at
    ])
    |> validate_required([
      :run_id,
      :prolific_participant_id,
      :prolific_study_id,
      :prolific_session_id,
      :consent_key,
      :consented_at,
      :status,
      :started_at
    ])
    |> validate_length(:prolific_participant_id, min: 1, max: 255)
    |> validate_length(:prolific_study_id, min: 1, max: 255)
    |> validate_length(:prolific_session_id, min: 1, max: 255)
    |> validate_length(:consent_key, min: 1, max: 255)
    |> validate_completion()
    |> foreign_key_constraint(:run_id)
    |> unique_constraint(:run_id)
    |> unique_constraint(:prolific_session_id)
    |> check_constraint(:prolific_participant_id,
      name: :participations_prolific_participant_id_not_blank
    )
    |> check_constraint(:prolific_study_id, name: :participations_prolific_study_id_not_blank)
    |> check_constraint(:prolific_session_id, name: :participations_prolific_session_id_not_blank)
    |> check_constraint(:consent_key, name: :participations_consent_key_not_blank)
    |> check_constraint(:status, name: :participations_status_valid)
    |> check_constraint(:completed_at, name: :participations_completion_consistent)
  end

  def statuses, do: @statuses

  defp validate_completion(changeset) do
    status = get_field(changeset, :status)
    completed_at = get_field(changeset, :completed_at)

    cond do
      status == :completed and is_nil(completed_at) ->
        add_error(changeset, :completed_at, "must be set when participation is completed")

      status != :completed and not is_nil(completed_at) ->
        add_error(changeset, :completed_at, "must be empty until participation is completed")

      true ->
        changeset
    end
  end
end
