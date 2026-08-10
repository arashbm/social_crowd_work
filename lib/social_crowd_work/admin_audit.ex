defmodule SocialCrowdWork.AdminAudit do
  @moduledoc """
  Records security-relevant administrator actions without participant data.
  """

  import Ecto.Query

  alias SocialCrowdWork.AdminAudit.AuditEvent
  alias SocialCrowdWork.Admins.Scope
  alias SocialCrowdWork.Repo

  def record(%Scope{admin: admin}, action, opts \\ []) when is_binary(action) do
    attrs = %{
      admin_id: admin.id,
      action: action,
      target_type: Keyword.get(opts, :target_type),
      target_id: Keyword.get(opts, :target_id),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    %AuditEvent{}
    |> AuditEvent.changeset(attrs)
    |> Repo.insert()
  end

  def list_events(%Scope{}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    AuditEvent
    |> order_by([event], desc: event.inserted_at, desc: event.id)
    |> limit(^limit)
    |> preload(:admin)
    |> Repo.all()
  end
end
