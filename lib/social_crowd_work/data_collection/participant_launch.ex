defmodule SocialCrowdWork.DataCollection.ParticipantLaunch do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.DataCollection.Participation
  alias SocialCrowdWork.Experiments.Condition

  @token_bytes 32
  @identifier_fields [:prolific_participant_id, :prolific_study_id, :prolific_session_id]

  schema "participant_launches" do
    field :token_hash, :binary
    field :prolific_participant_id, :string
    field :prolific_study_id, :string
    field :prolific_session_id, :string
    field :expires_at, :utc_datetime

    belongs_to :condition, Condition
    belongs_to :participation, Participation

    timestamps(type: :utc_datetime)
  end

  def changeset(%__MODULE__{} = launch, attrs) do
    launch
    |> cast(attrs, @identifier_fields ++ [:expires_at])
    |> validate_required([:token_hash, :condition_id, :expires_at | @identifier_fields])
    |> validate_token_hash()
    |> validate_identifiers()
    |> foreign_key_constraint(:condition_id)
    |> foreign_key_constraint(:participation_id)
    |> unique_constraint(:token_hash)
    |> check_constraint(:token_hash, name: :participant_launches_token_hash_length)
    |> check_constraint(:expires_at, name: :participant_launches_expiry_after_insert)
    |> identifier_constraints()
  end

  def create_changeset(
        %Condition{id: condition_id},
        participation,
        token_hash,
        attrs
      ) do
    %__MODULE__{
      condition_id: condition_id,
      participation_id: participation_id(participation),
      token_hash: token_hash
    }
    |> changeset(attrs)
  end

  def generate_token do
    token = :crypto.strong_rand_bytes(@token_bytes)
    {Base.url_encode64(token, padding: false), :crypto.hash(:sha256, token)}
  end

  def decode_token(raw_token) when is_binary(raw_token) do
    case Base.url_decode64(raw_token, padding: false) do
      {:ok, token} when byte_size(token) == @token_bytes -> {:ok, token}
      _other -> :error
    end
  end

  def decode_token(_raw_token), do: :error

  def hash_token(raw_token) do
    case decode_token(raw_token) do
      {:ok, token} -> {:ok, :crypto.hash(:sha256, token)}
      :error -> :error
    end
  end

  def expired?(%__MODULE__{expires_at: %DateTime{} = expires_at}, now \\ DateTime.utc_now()) do
    DateTime.compare(expires_at, now) != :gt
  end

  defp participation_id(nil), do: nil
  defp participation_id(%Participation{id: id}), do: id

  defp validate_token_hash(changeset) do
    case get_field(changeset, :token_hash) do
      token_hash when is_binary(token_hash) and byte_size(token_hash) == @token_bytes ->
        changeset

      nil ->
        changeset

      _token_hash ->
        add_error(changeset, :token_hash, "should be #{@token_bytes} byte(s)")
    end
  end

  defp validate_identifiers(changeset) do
    Enum.reduce(@identifier_fields, changeset, fn field, changeset ->
      validate_length(changeset, field, min: 1, max: 255)
    end)
  end

  defp identifier_constraints(changeset) do
    Enum.reduce(@identifier_fields, changeset, fn field, changeset ->
      check_constraint(changeset, field, name: "participant_launches_#{field}_not_blank")
    end)
  end
end
