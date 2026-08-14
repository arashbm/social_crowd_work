defmodule SocialCrowdWork.DataCollection.ParticipantEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.DataCollection.Participation
  alias SocialCrowdWork.Experiments.Task

  @kinds [
    :client_context,
    :task_rendered,
    :question_rendered,
    :question_exposure,
    :visibility_hidden,
    :visibility_visible,
    :window_blurred,
    :window_focused,
    :copy,
    :answer_created,
    :answer_changed
  ]

  schema "participant_events" do
    field :question_key, :string
    field :kind, Ecto.Enum, values: @kinds
    field :event_id, Ecto.UUID
    field :client_session_id, Ecto.UUID
    field :sequence, :integer
    field :client_elapsed_ms, :integer
    field :duration_ms, :integer
    field :client_occurred_at, :utc_datetime_usec
    field :server_received_at, :utc_datetime_usec
    field :metadata, :map, default: %{}

    belongs_to :participant, Participation, foreign_key: :participant_id
    belongs_to :task, Task

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :task_id,
      :question_key,
      :kind,
      :event_id,
      :client_session_id,
      :sequence,
      :client_elapsed_ms,
      :duration_ms,
      :client_occurred_at,
      :metadata
    ])
    |> validate_required([:participant_id, :kind, :event_id, :server_received_at, :metadata])
    |> validate_length(:question_key, min: 1, max: 255)
    |> validate_number(:sequence,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 9_007_199_254_740_991
    )
    |> validate_number(:client_elapsed_ms,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 604_800_000
    )
    |> validate_number(:duration_ms,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 604_800_000
    )
    |> validate_change(:metadata, fn :metadata, metadata ->
      if is_map(metadata), do: [], else: [metadata: "must be an object"]
    end)
    |> foreign_key_constraint(:participant_id)
    |> foreign_key_constraint(:task_id)
    |> unique_constraint(:event_id)
    |> check_constraint(:kind, name: :participant_events_kind_valid)
    |> check_constraint(:question_key, name: :participant_events_question_key_not_blank)
    |> check_constraint(:sequence, name: :participant_events_sequence_valid)
    |> check_constraint(:client_elapsed_ms, name: :participant_events_client_elapsed_ms_valid)
    |> check_constraint(:duration_ms, name: :participant_events_duration_ms_valid)
    |> check_constraint(:metadata, name: :participant_events_metadata_is_object)
  end

  def kinds, do: @kinds
end
