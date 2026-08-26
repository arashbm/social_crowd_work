defmodule SocialCrowdWorkWeb.AdminLive.ParticipationIndex do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{AdminAudit, AdminPanel, DataCollection}

  @impl true
  def mount(_params, _session, socket) do
    participations =
      socket.assigns.current_scope
      |> AdminPanel.list_participations()
      |> Enum.map(fn participation ->
        %{
          participation: participation,
          progress: AdminPanel.participation_progress(participation)
        }
      end)

    {:ok,
     socket
     |> assign(:page_title, "Participations")
     |> stream(:participations, participations,
       dom_id: fn %{participation: participation} -> "participation-#{participation.id}" end
     )}
  end

  @impl true
  def handle_event("copy_resume_link", %{"participation_id" => participation_id}, socket) do
    scope = socket.assigns.current_scope

    with {id, ""} <- Integer.parse(participation_id),
         participation when not is_nil(participation) <- AdminPanel.get_participation(scope, id),
         {:ok, launch_token} <- DataCollection.create_participant_resume_launch(participation),
         {:ok, _event} <-
           AdminAudit.record(scope, "participant_resume_link_generated",
             target_type: "participation",
             target_id: participation.id
           ) do
      {:reply, %{path: ~p"/participate/#{launch_token}"}, socket}
    else
      _error ->
        {:reply, %{error: "Unable to create a resume link."}, socket}
    end
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
              </th><th class="px-5 py-3">Status</th><th class="px-5 py-3">Started</th><th class="px-5 py-3 text-right">
                Actions
              </th>
            </tr>
          </thead>
          <tbody
            id="participations"
            phx-update="stream"
            class="divide-y divide-slate-100 dark:divide-slate-800"
          >
            <tr id="participations-empty" class="hidden only:table-row">
              <td colspan="6" class="px-5 py-12 text-center text-slate-500">
                No participations yet.
              </td>
            </tr>
            <tr
              :for={{id, row} <- @streams.participations}
              id={id}
              class="transition hover:bg-slate-50 dark:hover:bg-slate-800/60"
            >
              <td class="px-5 py-4">
                <.link
                  navigate={~p"/admin/participations/#{row.participation.id}"}
                  class="font-mono text-xs font-semibold text-indigo-700 hover:text-indigo-500 dark:text-indigo-300"
                >{mask_identifier(row.participation.prolific_participant_id)}</.link>
              </td>
              <td class="px-5 py-4">
                <p class="font-medium text-slate-900 dark:text-white">
                  {row.participation.run.condition.key}
                </p><p class="mt-1 text-xs text-slate-500">{row.participation.run.external_key}</p>
              </td>
              <td class="px-5 py-4 tabular-nums text-slate-600 dark:text-slate-300">
                <p>{row.progress.answered} / {row.progress.expected} questions</p>
                <p class="mt-1 text-xs text-slate-500">
                  {row.participation.instruction_pages_completed} instruction pages
                </p>
              </td>
              <td class="px-5 py-4"><.status_badge status={row.participation.status} /></td>
              <td class="px-5 py-4 text-xs text-slate-500">
                {Calendar.strftime(row.participation.started_at, "%Y-%m-%d %H:%M")}
              </td>
              <td class="px-5 py-4 text-right">
                <button
                  :if={row.participation.status in [:assigned, :in_progress]}
                  id={"copy-resume-link-#{row.participation.id}"}
                  type="button"
                  phx-hook=".CopyResumeLink"
                  phx-update="ignore"
                  data-participation-id={row.participation.id}
                  class="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-700 shadow-sm transition hover:border-indigo-300 hover:text-indigo-700 focus:outline-none focus:ring-2 focus:ring-indigo-500/30 disabled:cursor-wait disabled:opacity-60 dark:border-slate-700 dark:bg-slate-950 dark:text-slate-200 dark:hover:border-indigo-500 dark:hover:text-indigo-300"
                >
                  <.icon name="hero-clipboard" class="size-4" />
                  <span data-copy-label>Copy resume link</span>
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyResumeLink">
        export default {
          mounted() {
            this.label = this.el.querySelector("[data-copy-label]")
            this.defaultLabel = this.label.textContent

            this.el.addEventListener("click", () => {
              this.el.disabled = true
              this.label.textContent = "Creating link..."

              this.pushEvent("copy_resume_link", {
                participation_id: this.el.dataset.participationId
              }, async reply => {
                try {
                  if (!reply.path) throw new Error(reply.error || "Unable to create link")

                  const url = new URL(reply.path, window.location.origin).href
                  await navigator.clipboard.writeText(url)
                  this.label.textContent = "Copied"
                } catch (_error) {
                  this.label.textContent = "Copy failed"
                } finally {
                  window.setTimeout(() => {
                    this.label.textContent = this.defaultLabel
                    this.el.disabled = false
                  }, 1800)
                }
              })
            })
          }
        }
      </script>
    </Layouts.app>
    """
  end
end
