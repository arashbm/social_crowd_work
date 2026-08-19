defmodule SocialCrowdWorkWeb.AdminLive.ParticipationShow do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{AdminPanel, Questionnaires}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    participation = AdminPanel.get_participation!(socket.assigns.current_scope, id)
    responses = Map.new(participation.responses, &{{&1.task_id, &1.question_key}, &1})

    task_rows =
      participation.run.tasks
      |> Enum.sort_by(& &1.position)
      |> Enum.flat_map(fn task ->
        questionnaire = Questionnaires.fetch!(task.questionnaire_key)

        questionnaire.questions()
        |> Enum.with_index(1)
        |> Enum.map(fn {question, number} ->
          %{
            task: task,
            question: question,
            question_number: number,
            response: Map.get(responses, {task.id, question.key()})
          }
        end)
      end)

    {:ok,
     socket
     |> assign(:page_title, "Participation #{participation.id}")
     |> assign(:participation, participation)
     |> stream(:task_rows, task_rows,
       dom_id: fn row -> "task-#{row.task.id}-question-#{row.question_number}" end
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Participation #{@participation.id}"
        description="Sensitive participant identifiers and read-only response details."
      >
        <:actions><.status_badge status={@participation.status} /></:actions>
      </.admin_header>

      <section class="grid gap-4 lg:grid-cols-2">
        <div class="rounded-2xl border border-rose-200 bg-rose-50 p-5 dark:border-rose-900 dark:bg-rose-500/10">
          <p class="text-xs font-bold uppercase tracking-wider text-rose-700 dark:text-rose-300">
            Sensitive Prolific identifiers
          </p>
          <dl class="mt-4 space-y-3 text-sm">
            <div>
              <dt class="text-rose-700/70 dark:text-rose-300/70">Participant ID</dt><dd
                id="raw-prolific-participant-id"
                class="mt-1 break-all font-mono"
              >
                {@participation.prolific_participant_id}
              </dd>
            </div>
            <div>
              <dt class="text-rose-700/70 dark:text-rose-300/70">Study ID</dt><dd class="mt-1 break-all font-mono">
                {@participation.prolific_study_id}
              </dd>
            </div>
            <div>
              <dt class="text-rose-700/70 dark:text-rose-300/70">Session ID</dt><dd class="mt-1 break-all font-mono">
                {@participation.prolific_session_id}
              </dd>
            </div>
          </dl>
        </div>
        <div class="rounded-2xl border border-slate-200 bg-white p-5 dark:border-slate-800 dark:bg-slate-900">
          <p class="text-xs font-bold uppercase tracking-wider text-slate-500">Study metadata</p>
          <dl class="mt-4 grid gap-4 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-slate-500">Condition</dt><dd class="mt-1 font-semibold">
                {@participation.run.condition.key}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Run</dt><dd class="mt-1 font-semibold">
                {@participation.run.external_key}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Consent</dt><dd class="mt-1 font-semibold">
                {@participation.consent_key}
              </dd>
            </div>
            <div>
              <dt class="text-slate-500">Consented</dt><dd class="mt-1">
                {Calendar.strftime(@participation.consented_at, "%Y-%m-%d %H:%M UTC")}
              </dd>
            </div>
            <div id="participation-instructions-key">
              <dt class="text-slate-500">Instruction snapshot</dt>
              <dd class="mt-1 font-mono text-xs">{@participation.instructions_key || "None"}</dd>
            </div>
            <div id="participation-instruction-progress">
              <dt class="text-slate-500">Instruction progress</dt>
              <dd class="mt-1 font-semibold">{@participation.instruction_pages_completed} pages</dd>
            </div>
            <div id="participation-instructions-completed-at" class="sm:col-span-2">
              <dt class="text-slate-500">Instructions completed</dt>
              <dd class="mt-1">{format_timestamp(@participation.instructions_completed_at)}</dd>
            </div>
          </dl>
        </div>
      </section>

      <section class="mt-7">
        <h2 class="mb-4 text-lg font-semibold text-slate-950 dark:text-white">
          Task and question responses
        </h2>
        <div id="participation-responses" phx-update="stream" class="space-y-3">
          <article
            :for={{id, row} <- @streams.task_rows}
            id={id}
            class="flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white p-5 dark:border-slate-800 dark:bg-slate-900 sm:flex-row sm:items-center sm:justify-between"
          >
            <div>
              <p class="text-xs font-bold uppercase tracking-wider text-indigo-600 dark:text-indigo-300">
                Task {row.task.position} · Question {row.question_number}
              </p><p class="mt-1 font-medium">{row.task.questionnaire_key}</p>
              <code class="mt-1 block text-xs text-slate-500">{row.question.key()}</code>
            </div>
            <%= if row.response do %>
              <div class="text-right">
                <p class="font-semibold capitalize">
                  {display_choice(row.response.choice)}
                </p><p class="mt-1 text-xs text-slate-500">
                  {Calendar.strftime(row.response.answered_at, "%Y-%m-%d %H:%M:%S")}
                </p>
              </div>
            <% else %>
              <span class="text-sm font-medium text-slate-400">Unanswered</span>
            <% end %>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp display_choice(:equal), do: "Very close / neither (equal)"
  defp display_choice(choice), do: choice |> Atom.to_string() |> String.replace("_", " ")

  defp format_timestamp(nil), do: "Not completed"
  defp format_timestamp(timestamp), do: Calendar.strftime(timestamp, "%Y-%m-%d %H:%M UTC")
end
