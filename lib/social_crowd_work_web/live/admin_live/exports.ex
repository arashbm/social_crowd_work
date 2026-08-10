defmodule SocialCrowdWorkWeb.AdminLive.Exports do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.AdminPanel

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Exports")
     |> assign(:conditions, AdminPanel.list_condition_summaries(socket.assigns.current_scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Exports"
        description="Stream analysis-ready JSONL. Every assigned task is included, including unanswered tasks."
      />

      <div class="rounded-2xl border border-rose-200 bg-rose-50 p-5 text-sm text-rose-900 dark:border-rose-900 dark:bg-rose-500/10 dark:text-rose-200">
        <div class="flex gap-3">
          <.icon name="hero-lock-closed" class="mt-0.5 size-5 shrink-0" /><p>
            Exports include raw Prolific participant, study, and session identifiers. Store downloaded files as sensitive research data.
          </p>
        </div>
      </div>

      <section class="mt-6 overflow-hidden rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900">
        <div class="flex items-center justify-between border-b border-slate-200 px-5 py-4 dark:border-slate-800">
          <div>
            <h2 class="font-semibold text-slate-950 dark:text-white">All conditions</h2><p class="mt-1 text-xs text-slate-500">
              Complete cross-condition task dataset
            </p>
          </div>
          <a
            id="export-all"
            href={~p"/admin/exports/download"}
            class="rounded-xl bg-indigo-600 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500"
          >Download JSONL</a>
        </div>
        <div id="condition-exports" class="divide-y divide-slate-100 dark:divide-slate-800">
          <div :if={@conditions == []} class="px-5 py-10 text-center text-sm text-slate-500">
            No conditions available.
          </div>
          <div
            :for={summary <- @conditions}
            id={"export-condition-#{summary.condition.id}"}
            class="flex flex-col gap-3 px-5 py-4 sm:flex-row sm:items-center sm:justify-between"
          >
            <div>
              <p class="font-semibold text-slate-900 dark:text-white">{summary.condition.key}</p><p class="mt-1 text-xs text-slate-500">
                {summary.assigned_runs} assigned runs
              </p>
            </div>
            <a
              href={~p"/admin/exports/download?#{%{condition: summary.condition.key}}"}
              class="rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold transition hover:border-indigo-400 hover:bg-indigo-50 dark:border-slate-700 dark:hover:bg-indigo-500/10"
            >Download condition</a>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
