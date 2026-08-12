defmodule SocialCrowdWorkWeb.ParticipantLive do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{Consents, DataCollection, Experiments, Prompts}
  alias SocialCrowdWork.DataCollection.Participation
  alias SocialCrowdWork.Experiments.Condition
  alias SocialCrowdWorkWeb.ParticipantContexts

  @choices %{
    "post_a" => :post_a,
    "post_b" => :post_b,
    "equal" => :equal,
    "yes" => :yes,
    "no" => :no,
    "skip" => :skip
  }

  @impl true
  def mount(%{"context_token" => context_token}, session, socket) do
    socket =
      socket
      |> assign(:current_scope, %{})
      |> assign(:state, :loading)
      |> assign(:condition, nil)
      |> assign(:context_token, context_token)
      |> assign(:participant_context, nil)
      |> assign(:participation, nil)
      |> assign(:consent, nil)
      |> assign(:task, nil)
      |> assign(:prompt, nil)
      |> assign(:response, nil)
      |> assign(:total_tasks, 0)
      |> load_session(session, context_token)

    {:ok, socket}
  end

  @impl true
  def handle_event("accept_consent", _params, %{assigns: %{state: :consent}} = socket) do
    condition = socket.assigns.condition
    context = socket.assigns.participant_context

    case DataCollection.consent_and_assign_run(condition, context, condition.consent_key) do
      {:ok, participation} ->
        {:noreply, load_participation(socket, participation)}

      {:error, :no_runs_available} ->
        {:noreply, assign(socket, :state, :unavailable)}

      {:error, reason} ->
        {:noreply, assign_error(socket, reason)}
    end
  end

  def handle_event("accept_consent", _params, socket), do: {:noreply, socket}

  def handle_event(
        "answer",
        %{"choice" => choice, "position" => submitted_position},
        %{assigns: %{state: :task}} = socket
      ) do
    with {position, ""} <- Integer.parse(submitted_position),
         true <- position == socket.assigns.task.position,
         {:ok, choice} <- choice_from_string(choice),
         true <- choice in socket.assigns.prompt.choices(),
         {:ok, _response} <-
           DataCollection.record_response(
             socket.assigns.participation,
             socket.assigns.task.id,
             choice
           ) do
      advance(socket)
    else
      false ->
        {:noreply, socket}

      :error ->
        {:noreply, put_flash(socket, :error, "That keyboard action is not valid here.")}

      {:error, :participation_completed} ->
        {:noreply, load_completed(socket)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Your answer could not be saved.")}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("answer", _params, socket), do: {:noreply, socket}

  def handle_event("previous", _params, %{assigns: %{state: :task}} = socket) do
    previous_position = socket.assigns.task.position - 1

    if previous_position > 0 do
      {:noreply, load_task(socket, previous_position)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("previous", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:participant}>
      <div
        id="participant-shortcuts"
        phx-hook=".KeyboardShortcuts"
        class="mx-auto w-full max-w-5xl"
      >
        <%= case @state do %>
          <% :consent -> %>
            <.consent_panel consent={@consent} context_token={@context_token} />
          <% :task -> %>
            <.task_panel
              task={@task}
              prompt={@prompt}
              response={@response}
              total_tasks={@total_tasks}
            />
          <% :completed -> %>
            <.status_panel
              id="participation-completed"
              eyebrow="Study complete"
              title="Your responses have been recorded"
              message="Continue to Prolific to complete your submission and receive payment."
            >
              <a
                id="complete-on-prolific"
                href={~p"/participate/#{@context_token}/complete"}
                rel="noreferrer"
                data-shortcut="Enter,space"
                class="inline-flex items-center gap-3 rounded-xl bg-indigo-700 px-5 py-3 font-semibold text-white shadow-lg shadow-indigo-900/15 transition hover:-translate-y-0.5 hover:bg-indigo-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900"
              >
                Continue to Prolific <.flow_shortcuts />
              </a>
            </.status_panel>
          <% :unavailable -> %>
            <.status_panel
              id="participation-unavailable"
              eyebrow="Study unavailable"
              title="There are no tasks available"
              message="No study data was saved. Please return this submission from your Prolific submissions page."
            >
              <a
                id="unavailable-return-to-prolific"
                href="https://app.prolific.com/submissions"
                rel="noreferrer"
                data-shortcut="Enter,space"
                class="inline-flex items-center gap-3 rounded-xl bg-slate-900 px-5 py-3 font-semibold text-white transition hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900"
              >
                Open Prolific submissions <.flow_shortcuts />
              </a>
            </.status_panel>
          <% :error -> %>
            <.status_panel
              id="participation-error"
              eyebrow="Unable to continue"
              title="This participant session could not be verified"
              message="Return to Prolific and reopen the study from your submissions page."
            >
              <a
                id="error-return-to-prolific"
                href="https://app.prolific.com/submissions"
                rel="noreferrer"
                data-shortcut="Enter,space"
                class="inline-flex items-center gap-3 rounded-xl bg-slate-900 px-5 py-3 font-semibold text-white transition hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900"
              >
                Open Prolific submissions <.flow_shortcuts />
              </a>
            </.status_panel>
          <% _loading -> %>
            <div id="participant-loading" class="py-20 text-center text-slate-500 dark:text-slate-400">
              Loading study...
            </div>
        <% end %>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".KeyboardShortcuts">
          export default {
            mounted() {
              this.pending = false
              this.onKeydown = event => {
                if (this.pending || event.repeat || event.metaKey || event.ctrlKey || event.altKey) return
                if (["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName) || event.target.isContentEditable) return

                const key = event.code === "Space" ? "space" : (event.key.length === 1 ? event.key.toLowerCase() : event.key)
                const target = [...this.el.querySelectorAll("[data-shortcut]")].find(element =>
                  element.dataset.shortcut.split(",").map(value => value.trim().toLowerCase()).includes(key.toLowerCase())
                )

                if (!target || target.disabled || target.getAttribute("aria-disabled") === "true") return

                event.preventDefault()
                this.pending = true
                target.click()
              }
              window.addEventListener("keydown", this.onKeydown)
            },
            updated() {
              this.pending = false
            },
            destroyed() {
              window.removeEventListener("keydown", this.onKeydown)
            }
          }
        </script>
      </div>
    </Layouts.app>
    """
  end

  attr :consent, :any, required: true
  attr :context_token, :string, required: true

  defp consent_panel(assigns) do
    ~H"""
    <section
      id="consent-panel"
      class="mx-auto max-w-3xl overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-xl shadow-slate-900/5 transition-colors dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/20"
    >
      <div class="p-7 sm:p-11">
        {render_definition(@consent)}
      </div>
      <div class="flex flex-col-reverse gap-3 border-t border-slate-200 bg-slate-50 px-7 py-6 transition-colors dark:border-slate-700 dark:bg-slate-950/50 sm:flex-row sm:items-center sm:justify-between sm:px-11">
        <.link
          id="decline-consent"
          href={~p"/participate/#{@context_token}/decline"}
          class="inline-flex items-center justify-center gap-2 rounded-xl px-4 py-3 font-medium text-slate-600 transition hover:bg-slate-200 hover:text-slate-900 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-white"
        >
          I do not consent
        </.link>
        <button
          id="accept-consent"
          type="button"
          phx-click="accept_consent"
          phx-disable-with="Starting..."
          data-shortcut="Enter,space"
          class="inline-flex items-center justify-center gap-3 rounded-xl bg-indigo-700 px-5 py-3 font-semibold text-white shadow-lg shadow-indigo-900/15 transition hover:-translate-y-0.5 hover:bg-indigo-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900"
        >
          I consent and want to begin <.flow_shortcuts />
        </button>
      </div>
    </section>
    """
  end

  attr :task, :any, required: true
  attr :prompt, :any, required: true
  attr :response, :any, default: nil
  attr :total_tasks, :integer, required: true

  defp task_panel(assigns) do
    progress = round((assigns.task.position - 1) / assigns.total_tasks * 100)
    assigns = assign(assigns, :progress, progress)

    ~H"""
    <section id="task-panel" class="space-y-6">
      <header class="flex items-center gap-4" id="task-progress">
        <div class="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-200 dark:bg-slate-700">
          <div
            class="h-full rounded-full bg-indigo-600 transition-[width] duration-300"
            style={"width: #{@progress}%"}
          />
        </div>
        <p class="shrink-0 text-sm font-semibold tabular-nums text-slate-600 dark:text-slate-300">
          {@task.position} / {@total_tasks}
        </p>
      </header>

      <div class="rounded-3xl border border-slate-200 bg-white p-6 shadow-xl shadow-slate-900/5 transition-colors dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/20 sm:p-9">
        {render_definition(@prompt)}

        <%= if @prompt.task_type() == :comparison do %>
          <.comparison_actions task={@task} response={@response} />
        <% else %>
          <.binary_actions task={@task} response={@response} />
        <% end %>
      </div>

      <footer class="flex items-center justify-between gap-4">
        <button
          id="previous-task"
          type="button"
          phx-click="previous"
          data-shortcut="z"
          disabled={@task.position == 1}
          class="inline-flex items-center gap-2 rounded-xl px-4 py-2.5 font-medium text-slate-600 transition hover:bg-white hover:text-slate-950 disabled:cursor-not-allowed disabled:opacity-30 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-white"
        >
          <.shortcut_key>Z</.shortcut_key>
          Previous
        </button>
        <p class="text-right text-xs leading-5 text-slate-500 dark:text-slate-400 sm:text-sm">
          Keyboard shortcuts submit immediately
        </p>
      </footer>
    </section>
    """
  end

  attr :task, :any, required: true
  attr :response, :any, default: nil

  defp comparison_actions(assigns) do
    ~H"""
    <div class="mt-8 grid gap-4 md:grid-cols-2" id="comparison-posts">
      <.post_card
        id="post-a"
        label="Post A"
        text={@task.stimuli["post_a"]["text"]}
      />
      <.post_card
        id="post-b"
        label="Post B"
        text={@task.stimuli["post_b"]["text"]}
      />
    </div>
    <div id="comparison-answer-options" class="mt-4 grid gap-3 sm:grid-cols-3">
      <.compact_choice
        id="answer-post-a"
        label="Post A"
        shortcut="A"
        choice="post_a"
        position={@task.position}
        selected={selected?(@response, :post_a)}
      />
      <.compact_choice
        id="answer-equal"
        label="Equal"
        shortcut="S"
        choice="equal"
        position={@task.position}
        selected={selected?(@response, :equal)}
      />
      <.compact_choice
        id="answer-post-b"
        label="Post B"
        shortcut="D"
        choice="post_b"
        position={@task.position}
        selected={selected?(@response, :post_b)}
      />
    </div>
    <div
      id="comparison-skip"
      class="mt-6 flex justify-end border-t border-slate-200 pt-4 dark:border-slate-700"
    >
      <.skip_choice position={@task.position} selected={selected?(@response, :skip)} />
    </div>
    """
  end

  attr :task, :any, required: true
  attr :response, :any, default: nil

  defp binary_actions(assigns) do
    ~H"""
    <article
      id="single-post"
      class="mt-8 rounded-2xl border border-slate-200 bg-slate-50 p-6 transition-colors dark:border-slate-700 dark:bg-slate-950/60 sm:p-8"
    >
      <p class="whitespace-pre-wrap break-words text-base leading-7 text-slate-800 dark:text-slate-100 sm:text-lg">
        {@task.stimuli["post"]["text"]}
      </p>
    </article>
    <div id="binary-answer-options" class="mt-4 grid gap-3 sm:grid-cols-2">
      <.compact_choice
        id="answer-yes"
        label="Yes"
        shortcut="A"
        choice="yes"
        position={@task.position}
        selected={selected?(@response, :yes)}
      />
      <.compact_choice
        id="answer-no"
        label="No"
        shortcut="S"
        choice="no"
        position={@task.position}
        selected={selected?(@response, :no)}
      />
    </div>
    <div
      id="binary-skip"
      class="mt-6 flex justify-end border-t border-slate-200 pt-4 dark:border-slate-700"
    >
      <.skip_choice position={@task.position} selected={selected?(@response, :skip)} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :text, :string, required: true

  defp post_card(assigns) do
    ~H"""
    <article
      id={@id}
      class="flex min-h-56 flex-col overflow-hidden rounded-2xl border border-slate-200 bg-slate-50 transition-colors dark:border-slate-700 dark:bg-slate-950/60"
    >
      <span class="border-b border-slate-200 px-6 py-3 text-xs font-bold uppercase tracking-[0.14em] text-indigo-700 dark:border-slate-700 dark:text-indigo-300 sm:px-7">
        {@label}
      </span>
      <span class="flex-1 whitespace-pre-wrap break-words p-6 text-base leading-7 text-slate-800 dark:text-slate-100 sm:p-7 sm:text-lg">
        {@text}
      </span>
    </article>
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :shortcut, :string, required: true
  attr :choice, :string, required: true
  attr :position, :integer, required: true
  attr :selected, :boolean, default: false

  defp compact_choice(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="answer"
      phx-value-choice={@choice}
      phx-value-position={@position}
      data-shortcut={String.downcase(@shortcut)}
      aria-pressed={to_string(@selected)}
      class={[
        "inline-flex items-center justify-between gap-3 rounded-xl border px-5 py-3.5 font-semibold transition focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-slate-900",
        @selected &&
          "border-indigo-600 bg-indigo-700 text-white dark:border-indigo-400 dark:bg-indigo-500/30",
        not @selected &&
          "border-slate-300 bg-white text-slate-800 hover:border-indigo-400 hover:bg-indigo-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:hover:border-indigo-400 dark:hover:bg-indigo-500/15 dark:focus:ring-offset-slate-900"
      ]}
    >
      {@label}
      <.shortcut_key>{@shortcut}</.shortcut_key>
    </button>
    """
  end

  attr :position, :integer, required: true
  attr :selected, :boolean, default: false

  defp skip_choice(assigns) do
    ~H"""
    <button
      id="answer-skip"
      type="button"
      phx-click="answer"
      phx-value-choice="skip"
      phx-value-position={@position}
      data-shortcut="x"
      aria-pressed={to_string(@selected)}
      class={[
        "inline-flex items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium transition focus:outline-none focus:ring-2 focus:ring-indigo-500",
        if(@selected,
          do: "bg-slate-200 text-slate-950 dark:bg-slate-700 dark:text-white",
          else:
            "text-slate-500 hover:bg-slate-100 hover:text-slate-800 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-100"
        )
      ]}
    >
      Skip this task
      <.shortcut_key>X</.shortcut_key>
    </button>
    """
  end

  attr :id, :string, required: true
  attr :eyebrow, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true
  slot :inner_block, required: true

  defp status_panel(assigns) do
    ~H"""
    <section
      id={@id}
      class="mx-auto max-w-xl rounded-3xl border border-slate-200 bg-white p-8 shadow-xl shadow-slate-900/5 transition-colors dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/20 sm:p-12"
    >
      <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700 dark:text-indigo-300">
        {@eyebrow}
      </p>
      <h1 class="mt-3 text-3xl font-semibold tracking-tight text-slate-950 dark:text-white">
        {@title}
      </h1>
      <p class="mt-5 leading-7 text-slate-600 dark:text-slate-300">{@message}</p>
      <div class="mt-8">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  slot :inner_block, required: true

  defp shortcut_key(assigns) do
    ~H"""
    <kbd class="inline-flex min-w-7 items-center justify-center rounded-md border border-current/20 bg-white/70 px-1.5 py-0.5 font-mono text-xs font-bold leading-5 text-current shadow-sm dark:bg-slate-950/50">
      {render_slot(@inner_block)}
    </kbd>
    """
  end

  defp flow_shortcuts(assigns) do
    ~H"""
    <span class="inline-flex items-center gap-1.5">
      <.shortcut_key>Enter</.shortcut_key>
      <span class="text-xs font-medium opacity-70">or</span>
      <.shortcut_key>Space</.shortcut_key>
    </span>
    """
  end

  defp load_session(socket, session, context_token) do
    with {:ok, context} <- ParticipantContexts.fetch(session, context_token),
         condition_id when is_integer(condition_id) <- Map.get(context, "condition_id"),
         %Condition{} = condition <- Experiments.get_condition(condition_id),
         participant_context <- participant_attrs(context) do
      socket =
        socket
        |> assign(:condition, condition)
        |> assign(:participant_context, participant_context)

      case DataCollection.resume_participation(condition, participant_context) do
        {:ok, participation} -> load_participation(socket, participation)
        {:error, :not_found} -> load_consent(socket, condition)
        {:error, reason} -> assign_error(socket, reason)
      end
    else
      _other -> assign_error(socket, :invalid_session)
    end
  end

  defp load_consent(socket, %Condition{status: status}) when status != :active,
    do: assign(socket, :state, :unavailable)

  defp load_consent(socket, condition) do
    case Consents.fetch(condition.consent_key) do
      {:ok, consent} -> socket |> assign(:consent, consent) |> assign(:state, :consent)
      :error -> assign_error(socket, :unknown_consent)
    end
  end

  defp load_participation(socket, %Participation{status: :completed} = participation) do
    socket
    |> assign(:participation, participation)
    |> load_completed()
  end

  defp load_participation(socket, participation) do
    socket = assign(socket, :participation, participation)

    case DataCollection.next_unanswered_task(participation) do
      nil ->
        case DataCollection.complete_participation(participation) do
          {:ok, completed} -> socket |> assign(:participation, completed) |> load_completed()
          {:error, reason} -> assign_error(socket, reason)
        end

      task ->
        load_task(socket, task.position)
    end
  end

  defp load_task(socket, position) do
    case DataCollection.task_page(socket.assigns.participation, position) do
      {:ok, page} ->
        case Prompts.fetch(page.task.prompt_key) do
          {:ok, prompt} ->
            socket
            |> assign(:task, page.task)
            |> assign(:prompt, prompt)
            |> assign(:response, page.response)
            |> assign(:total_tasks, page.total_tasks)
            |> assign(:state, :task)

          :error ->
            assign_error(socket, :unknown_prompt)
        end

      {:error, reason} ->
        assign_error(socket, reason)
    end
  end

  defp advance(socket) do
    if socket.assigns.task.position < socket.assigns.total_tasks do
      {:noreply, load_task(socket, socket.assigns.task.position + 1)}
    else
      case DataCollection.complete_participation(socket.assigns.participation) do
        {:ok, completed} ->
          socket = socket |> assign(:participation, completed) |> load_completed()

          {:noreply,
           redirect(socket, to: ~p"/participate/#{socket.assigns.context_token}/complete")}

        {:error, reason} ->
          {:noreply, assign_error(socket, reason)}
      end
    end
  end

  defp load_completed(socket), do: assign(socket, :state, :completed)

  defp assign_error(socket, _reason), do: assign(socket, :state, :error)

  defp participant_attrs(context) do
    %{
      prolific_participant_id: Map.get(context, "prolific_participant_id"),
      prolific_study_id: Map.get(context, "prolific_study_id"),
      prolific_session_id: Map.get(context, "prolific_session_id")
    }
  end

  defp choice_from_string(choice) do
    case Map.fetch(@choices, choice) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  defp selected?(nil, _choice), do: false
  defp selected?(response, choice), do: response.choice == choice

  defp render_definition(module), do: module.render(%{})
end
