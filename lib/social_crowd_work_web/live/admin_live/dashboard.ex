defmodule SocialCrowdWorkWeb.AdminLive.Dashboard do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{AdminAudit, AdminPanel}

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "Admin overview")
     |> assign(:stats, AdminPanel.dashboard_stats(scope))
     |> assign(:recent_events, AdminAudit.list_events(scope, limit: 6))
     |> stream(:conditions, AdminPanel.list_condition_summaries(scope),
       dom_id: fn %{condition: condition} -> "condition-#{condition.id}" end
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Overview"
        description="Recruitment capacity, collection progress, and recent administrative activity."
      >
        <:actions>
          <.link
            navigate={~p"/admin/imports"}
            class="rounded-xl bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500"
          >
            Import manifest
          </.link>
        </:actions>
      </.admin_header>

      <section id="admin-stats" class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <.stat_card label="Active conditions" value={@stats.active_conditions} icon="hero-bolt" />
        <.stat_card
          label="Available runs"
          value={@stats.available_runs}
          icon="hero-inbox-stack"
          tone={:emerald}
        />
        <.stat_card label="In progress" value={@stats.in_progress} icon="hero-clock" tone={:amber} />
        <.stat_card label="Completed" value={@stats.completed} icon="hero-check-circle" tone={:slate} />
      </section>

      <div class="mt-8 grid gap-6 xl:grid-cols-[minmax(0,1.5fr)_minmax(20rem,0.7fr)]">
        <section class="rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900">
          <div class="flex items-center justify-between border-b border-slate-200 px-5 py-4 dark:border-slate-800">
            <h2 class="font-semibold text-slate-950 dark:text-white">Conditions</h2>
            <.link
              navigate={~p"/admin/conditions"}
              class="text-sm font-semibold text-indigo-700 hover:text-indigo-500 dark:text-indigo-300"
            >View all</.link>
          </div>
          <div
            id="dashboard-conditions"
            phx-update="stream"
            class="divide-y divide-slate-100 dark:divide-slate-800"
          >
            <div
              id="dashboard-conditions-empty"
              class="hidden only:block px-5 py-10 text-center text-sm text-slate-500"
            >
              No conditions imported yet.
            </div>
            <.link
              :for={{id, summary} <- @streams.conditions}
              id={id}
              navigate={~p"/admin/conditions/#{summary.condition.id}"}
              class="flex items-center justify-between gap-4 px-5 py-4 transition hover:bg-slate-50 dark:hover:bg-slate-800/60"
            >
              <div class="min-w-0">
                <p class="truncate font-semibold text-slate-900 dark:text-white">
                  {summary.condition.key}
                </p>
                <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                  {summary.available_runs} available of {summary.total_runs} runs
                </p>
              </div>
              <.status_badge status={summary.condition.status} />
            </.link>
          </div>
        </section>

        <section class="rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900">
          <div class="border-b border-slate-200 px-5 py-4 dark:border-slate-800">
            <h2 class="font-semibold text-slate-950 dark:text-white">Recent audit activity</h2>
          </div>
          <div id="recent-audit" class="divide-y divide-slate-100 dark:divide-slate-800">
            <div :if={@recent_events == []} class="px-5 py-10 text-center text-sm text-slate-500">
              No admin actions recorded yet.
            </div>
            <div :for={event <- @recent_events} id={"recent-audit-#{event.id}"} class="px-5 py-4">
              <p class="text-sm font-semibold text-slate-800 dark:text-slate-200">{event.action}</p>
              <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
                {event.admin.email} · {Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")}
              </p>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
