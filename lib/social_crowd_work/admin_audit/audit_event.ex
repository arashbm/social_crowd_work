defmodule SocialCrowdWork.AdminAudit.AuditEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialCrowdWork.Admins.Admin

  schema "admin_audit_events" do
    field :action, :string
    field :target_type, :string
    field :target_id, :integer
    field :metadata, :map, default: %{}

    belongs_to :admin, Admin

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:admin_id, :action, :target_type, :target_id, :metadata])
    |> validate_required([:admin_id, :action, :metadata])
    |> validate_length(:action, min: 1, max: 255)
    |> validate_length(:target_type, max: 255)
    |> foreign_key_constraint(:admin_id)
    |> check_constraint(:action, name: :admin_audit_events_action_not_blank)
    |> check_constraint(:metadata, name: :admin_audit_events_metadata_is_object)
  end
end
