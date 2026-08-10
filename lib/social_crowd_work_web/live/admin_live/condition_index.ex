defmodule SocialCrowdWorkWeb.AdminLive.ConditionIndex do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.AdminPanel

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Conditions")
     |> stream(:conditions, AdminPanel.list_condition_summaries(socket.assigns.current_scope),
       dom_id: fn %{condition: condition} -> "condition-#{condition.id}" end
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Conditions"
        description="Configure recruitment while preserving imported task design."
      />

      <div id="conditions" phx-update="stream" class="grid gap-4 xl:grid-cols-2">
        <div id="conditions-empty-wrapper" class="hidden only:block">
          <.admin_empty
            id="conditions-empty"
            title="No conditions"
            message="Import a manifest to create your first condition."
          />
        </div>
        <.link
          :for={{id, summary} <- @streams.conditions}
          id={id}
          navigate={~p"/admin/conditions/#{summary.condition.id}"}
          class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm transition hover:-translate-y-0.5 hover:border-indigo-300 hover:shadow-md dark:border-slate-800 dark:bg-slate-900 dark:hover:border-indigo-700"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0">
              <h2 class="truncate font-semibold text-slate-950 dark:text-white">
                {summary.condition.key}
              </h2>
              <p class="mt-1 text-sm capitalize text-slate-500 dark:text-slate-400">
                {summary.condition.task_type |> Atom.to_string() |> String.replace("_", " ")}
              </p>
            </div>
            <.status_badge status={summary.condition.status} />
          </div>
          <div class="mt-5 grid grid-cols-3 gap-3 border-t border-slate-100 pt-4 text-center dark:border-slate-800">
            <div>
              <p class="text-xl font-semibold">{summary.available_runs}</p><p class="text-xs text-slate-500">
                Available
              </p>
            </div>
            <div>
              <p class="text-xl font-semibold">{summary.assigned_runs}</p><p class="text-xs text-slate-500">
                Assigned
              </p>
            </div>
            <div>
              <p class="text-xl font-semibold">{summary.completed_runs}</p><p class="text-xs text-slate-500">
                Complete
              </p>
            </div>
          </div>
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
