defmodule SocialCrowdWorkWeb.AdminLive.ConditionShow do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{AdminAudit, AdminPanel, Consents}

  @status_map %{"draft" => :draft, "active" => :active, "paused" => :paused, "closed" => :closed}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    summary = AdminPanel.get_condition_summary!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, summary.condition.key)
     |> assign(:summary, summary)
     |> assign(
       :form,
       to_form(AdminPanel.change_condition(socket.assigns.current_scope, summary.condition))
     )
     |> assign(:consent_options, Enum.map(Consents.all(), &{&1.key(), &1.key()}))
     |> assign(:entry_url, entry_url(summary.condition))
     |> stream(
       :runs,
       AdminPanel.list_run_summaries(socket.assigns.current_scope, summary.condition.id)
     )}
  end

  @impl true
  def handle_event("validate", %{"condition" => params}, socket) do
    form =
      socket.assigns.current_scope
      |> AdminPanel.change_condition(socket.assigns.summary.condition, params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"condition" => params}, socket) do
    scope = socket.assigns.current_scope
    condition = socket.assigns.summary.condition

    case AdminPanel.configure_condition(scope, condition, params) do
      {:ok, condition} ->
        {:ok, _event} =
          AdminAudit.record(scope, "condition_configured",
            target_type: "condition",
            target_id: condition.id,
            metadata: %{"condition_key" => condition.key}
          )

        {:noreply,
         socket |> refresh(condition.id) |> put_flash(:info, "Condition configuration saved.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    with {:ok, status} <- Map.fetch(@status_map, status),
         {:ok, condition} <-
           AdminPanel.set_condition_status(
             socket.assigns.current_scope,
             socket.assigns.summary.condition,
             status
           ) do
      {:ok, _event} =
        AdminAudit.record(socket.assigns.current_scope, "condition_status_changed",
          target_type: "condition",
          target_id: condition.id,
          metadata: %{"condition_key" => condition.key, "status" => Atom.to_string(status)}
        )

      {:noreply,
       socket |> refresh(condition.id) |> put_flash(:info, "Condition is now #{status}.")}
    else
      :error ->
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset))
         |> put_flash(:error, "Condition status could not be changed.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title={@summary.condition.key}
        description="Operational configuration and immutable run inventory."
      >
        <:actions><.status_badge status={@summary.condition.status} /></:actions>
      </.admin_header>

      <div class="grid gap-6 xl:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="space-y-6">
          <section class="rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900">
            <h2 class="font-semibold text-slate-950 dark:text-white">Recruitment configuration</h2>
            <.form
              for={@form}
              id="condition-config-form"
              phx-change="validate"
              phx-submit="save"
              class="mt-5 grid gap-5 sm:grid-cols-2"
            >
              <.input field={@form[:prolific_study_id]} type="text" label="Prolific study ID" />
              <.input field={@form[:prolific_completion_code]} type="text" label="Completion code" />
              <div class="sm:col-span-2">
                <.input
                  field={@form[:consent_key]}
                  type="select"
                  label="Consent definition"
                  prompt="Select consent"
                  options={@consent_options}
                />
              </div>
              <div class="sm:col-span-2 flex justify-end">
                <button
                  id="save-condition-config"
                  class="rounded-xl bg-indigo-600 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-500"
                >Save configuration</button>
              </div>
            </.form>
          </section>

          <section class="rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900">
            <h2 class="font-semibold text-slate-950 dark:text-white">Prolific external study URL</h2>
            <p class="mt-2 text-sm text-slate-500 dark:text-slate-400">
              Use this exact URL in Prolific after configuring the condition.
            </p>
            <code
              id="condition-entry-url"
              class="mt-4 block overflow-x-auto rounded-xl bg-slate-950 px-4 py-3 text-xs leading-5 text-emerald-300"
            >{@entry_url}</code>
          </section>

          <section>
            <div class="mb-4 flex items-center justify-between">
              <h2 class="text-lg font-semibold text-slate-950 dark:text-white">Runs</h2>
              <span class="text-sm text-slate-500">{@summary.available_runs} available</span>
            </div>
            <div
              id="condition-runs"
              phx-update="stream"
              class="overflow-hidden rounded-2xl border border-slate-200 bg-white dark:border-slate-800 dark:bg-slate-900"
            >
              <div
                id="condition-runs-empty"
                class="hidden only:block px-6 py-12 text-center text-sm text-slate-500"
              >
                No imported runs.
              </div>
              <.link
                :for={{id, run} <- @streams.runs}
                id={id}
                navigate={~p"/admin/runs/#{run.id}"}
                class="flex items-center justify-between border-b border-slate-100 px-5 py-4 last:border-b-0 hover:bg-slate-50 dark:border-slate-800 dark:hover:bg-slate-800/60"
              >
                <div>
                  <p class="font-semibold text-slate-900 dark:text-white">{run.external_key}</p><p class="mt-1 text-xs text-slate-500">
                    {length(run.tasks)} tasks
                  </p>
                </div>
                <span class="text-sm text-slate-500">{if run.participation,
                  do: Atom.to_string(run.participation.status),
                  else: "available"}</span>
              </.link>
            </div>
          </section>
        </div>

        <aside class="space-y-6">
          <section class="rounded-2xl border border-slate-200 bg-white p-5 dark:border-slate-800 dark:bg-slate-900">
            <h2 class="font-semibold text-slate-950 dark:text-white">Lifecycle</h2>
            <div class="mt-4 grid gap-2">
              <button
                :for={status <- [:draft, :active, :paused, :closed]}
                id={"set-status-#{status}"}
                type="button"
                phx-click="set_status"
                phx-value-status={status}
                disabled={@summary.condition.status == status}
                data-confirm={status == :closed && "Close this condition to new recruitment?"}
                class="flex items-center justify-between rounded-xl border border-slate-200 px-3 py-2.5 text-left text-sm font-semibold capitalize transition hover:border-indigo-400 hover:bg-indigo-50 disabled:cursor-default disabled:border-indigo-500 disabled:bg-indigo-50 disabled:text-indigo-800 dark:border-slate-700 dark:hover:bg-indigo-500/10 dark:disabled:bg-indigo-500/15 dark:disabled:text-indigo-300"
              >
                {status}<span :if={@summary.condition.status == status}>Current</span>
              </button>
            </div>
          </section>
          <section class="rounded-2xl border border-slate-200 bg-white p-5 dark:border-slate-800 dark:bg-slate-900">
            <h2 class="font-semibold text-slate-950 dark:text-white">Design</h2>
            <dl class="mt-4 space-y-4 text-sm">
              <div>
                <dt class="text-slate-500">Task type</dt><dd class="mt-1 font-medium capitalize">
                  {@summary.condition.task_type |> Atom.to_string() |> String.replace("_", " ")}
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Variants</dt><dd class="mt-1">
                  <code class="break-all text-xs">{Jason.encode!(@summary.condition.variants)}</code>
                </dd>
              </div>
              <div>
                <dt class="text-slate-500">Capacity</dt><dd class="mt-1 font-medium">
                  {@summary.total_runs} total / {@summary.available_runs} available
                </dd>
              </div>
            </dl>
          </section>
        </aside>
      </div>
    </Layouts.app>
    """
  end

  defp refresh(socket, id) do
    summary = AdminPanel.get_condition_summary!(socket.assigns.current_scope, id)

    socket
    |> assign(:summary, summary)
    |> assign(
      :form,
      to_form(AdminPanel.change_condition(socket.assigns.current_scope, summary.condition))
    )
    |> assign(:entry_url, entry_url(summary.condition))
    |> stream(
      :runs,
      AdminPanel.list_run_summaries(socket.assigns.current_scope, summary.condition.id),
      reset: true
    )
  end

  defp entry_url(condition) do
    url(~p"/enter/#{condition.entry_token}") <>
      "?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}"
  end
end
