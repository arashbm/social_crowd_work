defmodule SocialCrowdWorkWeb.AdminLive.Audit do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.AdminAudit

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Audit log")
     |> stream(:events, AdminAudit.list_events(socket.assigns.current_scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Audit log"
        description="Security-relevant administrator actions. Participant identifiers are deliberately excluded."
      />

      <div
        id="audit-events"
        phx-update="stream"
        class="overflow-hidden rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900"
      >
        <div
          id="audit-events-empty"
          class="hidden only:block px-6 py-12 text-center text-sm text-slate-500"
        >
          No audit events yet.
        </div>
        <article
          :for={{id, event} <- @streams.events}
          id={id}
          class="grid gap-3 border-b border-slate-100 px-5 py-4 last:border-b-0 dark:border-slate-800 md:grid-cols-[minmax(0,1fr)_14rem_11rem] md:items-center"
        >
          <div>
            <p class="font-semibold text-slate-900 dark:text-white">{event.action}</p><p
              :if={event.target_type}
              class="mt-1 text-xs text-slate-500"
            >
              {event.target_type} {event.target_id}
            </p>
          </div>
          <p class="truncate text-sm text-slate-600 dark:text-slate-300">{event.admin.email}</p>
          <time class="text-xs text-slate-500">{Calendar.strftime(
            event.inserted_at,
            "%Y-%m-%d %H:%M:%S"
          )}</time>
        </article>
      </div>
    </Layouts.app>
    """
  end
end
