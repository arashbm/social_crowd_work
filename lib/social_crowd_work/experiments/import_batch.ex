defmodule SocialCrowdWork.Experiments.ImportBatch do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.Experiments.Run

  schema "import_batches" do
    field :original_filename, :string
    field :source_sha256, :string
    field :format_version, :string
    field :imported_at, :utc_datetime

    has_many :runs, Run

    timestamps(type: :utc_datetime)
  end

  def changeset(import_batch, attrs) do
    import_batch
    |> cast(attrs, [:original_filename, :source_sha256, :format_version, :imported_at])
    |> validate_required([:original_filename, :source_sha256, :format_version, :imported_at])
    |> validate_length(:original_filename, min: 1, max: 255)
    |> validate_format(:source_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_length(:format_version, min: 1, max: 255)
    |> unique_constraint(:source_sha256)
    |> check_constraint(:original_filename, name: :import_batches_filename_not_blank)
    |> check_constraint(:source_sha256, name: :import_batches_sha256_valid)
    |> check_constraint(:format_version, name: :import_batches_format_version_not_blank)
  end
end
