defmodule SocialCrowdWorkWeb.AdminLive.ParticipationIndex do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.AdminPanel

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Participations")
     |> stream(:participations, AdminPanel.list_participations(socket.assigns.current_scope))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Participations"
        description="Operational monitoring only. Participant responses remain immutable."
      />

      <div class="overflow-x-auto rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900">
        <table class="w-full min-w-[760px] text-left text-sm">
          <thead class="border-b border-slate-200 bg-slate-50 text-xs uppercase tracking-wider text-slate-500 dark:border-slate-800 dark:bg-slate-950/50 dark:text-slate-400">
            <tr>
              <th class="px-5 py-3">Participant</th><th class="px-5 py-3">Condition</th><th class="px-5 py-3">
                Progress
              </th><th class="px-5 py-3">Status</th><th class="px-5 py-3">Started</th>
            </tr>
          </thead>
          <tbody
            id="participations"
            phx-update="stream"
            class="divide-y divide-slate-100 dark:divide-slate-800"
          >
            <tr id="participations-empty" class="hidden only:table-row">
              <td colspan="5" class="px-5 py-12 text-center text-slate-500">
                No participations yet.
              </td>
            </tr>
            <tr
              :for={{id, participation} <- @streams.participations}
              id={id}
              class="transition hover:bg-slate-50 dark:hover:bg-slate-800/60"
            >
              <td class="px-5 py-4">
                <.link
                  navigate={~p"/admin/participations/#{participation.id}"}
                  class="font-mono text-xs font-semibold text-indigo-700 hover:text-indigo-500 dark:text-indigo-300"
                >{mask_identifier(participation.prolific_participant_id)}</.link>
              </td>
              <td class="px-5 py-4">
                <p class="font-medium text-slate-900 dark:text-white">
                  {participation.run.condition.key}
                </p><p class="mt-1 text-xs text-slate-500">{participation.run.external_key}</p>
              </td>
              <td class="px-5 py-4 tabular-nums text-slate-600 dark:text-slate-300">
                {length(participation.responses)} / {length(participation.run.tasks)}
              </td>
              <td class="px-5 py-4"><.status_badge status={participation.status} /></td>
              <td class="px-5 py-4 text-xs text-slate-500">
                {Calendar.strftime(participation.started_at, "%Y-%m-%d %H:%M")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
