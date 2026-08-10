defmodule SocialCrowdWorkWeb.AdminLive.RunShow do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{AdminPanel, Prompts}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    run = AdminPanel.get_run!(socket.assigns.current_scope, id)

    {:ok,
     socket
     |> assign(:page_title, run.external_key)
     |> assign(:run, run)
     |> stream(:tasks, run.tasks)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title={@run.external_key}
        description="Read-only inspection of the imported run and task payloads."
      >
        <:actions>
          <.link
            navigate={~p"/admin/conditions/#{@run.condition.id}"}
            class="rounded-xl border border-slate-300 px-4 py-2 text-sm font-semibold dark:border-slate-700"
          >Back to condition</.link>
        </:actions>
      </.admin_header>

      <section class="mb-6 grid gap-4 sm:grid-cols-3">
        <.stat_card label="Tasks" value={length(@run.tasks)} icon="hero-queue-list" />
        <.stat_card
          label="Import batch"
          value={@run.import_batch.id}
          icon="hero-arrow-up-tray"
          tone={:slate}
        />
        <.stat_card
          label="Assignment"
          value={if(@run.participation, do: @run.participation.status, else: "available")}
          icon="hero-user"
          tone={:emerald}
        />
      </section>

      <div id="run-tasks" phx-update="stream" class="space-y-5">
        <article
          :for={{id, task} <- @streams.tasks}
          id={id}
          class="rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p class="text-xs font-bold uppercase tracking-wider text-indigo-600 dark:text-indigo-300">
                Task {task.position}
              </p><h2 class="mt-1 font-semibold text-slate-950 dark:text-white">{task.prompt_key}</h2>
            </div>
            <span class="rounded-lg bg-slate-100 px-2.5 py-1 text-xs font-semibold dark:bg-slate-800">{prompt_status(
              task.prompt_key
            )}</span>
          </div>
          <pre class="mt-5 overflow-x-auto rounded-xl bg-slate-950 p-4 text-xs leading-5 text-slate-200"><code>{Jason.encode!(task.stimuli, pretty: true)}</code></pre>
        </article>
      </div>
    </Layouts.app>
    """
  end

  defp prompt_status(key) do
    case Prompts.fetch(key) do
      {:ok, _prompt} -> "Prompt available"
      :error -> "Prompt missing"
    end
  end
end
