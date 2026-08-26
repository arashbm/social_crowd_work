defmodule SocialCrowdWorkWeb.ParticipantLive do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{Consents, DataCollection, ParticipantEvents}
  alias SocialCrowdWork.DataCollection.Participation
  alias SocialCrowdWork.Experiments.Condition

  @choices %{
    "post_a" => :post_a,
    "post_b" => :post_b,
    "equal" => :equal,
    "yes" => :yes,
    "no" => :no,
    "skip" => :skip
  }

  @impl true
  def mount(%{"launch_token" => launch_token}, _session, socket) do
    socket =
      socket
      |> assign(:current_scope, %{})
      |> assign(:state, :loading)
      |> assign(:condition, nil)
      |> assign(:launch_token, launch_token)
      |> assign(:participant_context, nil)
      |> assign(:participation, nil)
      |> assign(:consent, nil)
      |> assign(:task, nil)
      |> assign(:questionnaire, nil)
      |> assign(:questions, [])
      |> assign(:active_question_key, nil)
      |> assign(:detailed_instructions_question_key, nil)
      |> assign(:total_tasks, 0)
      |> assign(:navigation_mode, :forward)
      |> assign(:frontier_position, nil)
      |> assign(:instruction_page, nil)
      |> assign(:instruction_review_index, nil)
      |> load_launch(launch_token)

    {:ok, socket}
  end

  @impl true
  def handle_event("accept_consent", _params, %{assigns: %{state: :consent}} = socket) do
    case DataCollection.consent_and_assign_run(
           socket.assigns.launch_token,
           socket.assigns.condition.consent_key
         ) do
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
        "participant_events",
        %{"events" => events},
        %{assigns: %{participation: %Participation{consented_at: consented_at} = participation}} =
          socket
      )
      when is_list(events) and not is_nil(consented_at) do
    accepted_ids =
      case ParticipantEvents.ingest_batch(participation, events) do
        {:ok, accepted_ids} when is_list(accepted_ids) -> accepted_ids
        {:ok, %{accepted_ids: accepted_ids}} when is_list(accepted_ids) -> accepted_ids
        accepted_ids when is_list(accepted_ids) -> accepted_ids
        _other -> []
      end

    {:reply, %{accepted_ids: accepted_ids}, socket}
  end

  def handle_event("participant_events", _params, socket) do
    {:reply, %{accepted_ids: []}, socket}
  end

  def handle_event(
        "answer",
        %{
          "choice" => choice,
          "position" => submitted_position,
          "question_key" => question_key
        },
        %{assigns: %{state: :task}} = socket
      ) do
    with {position, ""} <- Integer.parse(submitted_position),
         true <- position == socket.assigns.task.position,
         true <- question_key == socket.assigns.active_question_key,
         %{module: question} <- question_by_key(socket.assigns.questions, question_key),
         {:ok, choice} <- choice_from_string(choice),
         true <- choice in question.choices(),
         {:ok, _response} <-
           DataCollection.record_response(
             socket.assigns.participation,
             socket.assigns.task.id,
             question_key,
             choice
           ) do
      after_answer(socket)
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

  def handle_event("next_instruction", _params, %{assigns: %{state: :instructions}} = socket) do
    page = socket.assigns.instruction_page

    if socket.assigns.instruction_review_index < page.page_number do
      {:noreply,
       socket
       |> assign(:instruction_review_index, socket.assigns.instruction_review_index + 1)
       |> push_event("scroll_to_top", %{})}
    else
      case DataCollection.advance_instruction_page(
             socket.assigns.participation,
             page.page_number
           ) do
        {:ok, participation} ->
          {:noreply,
           socket
           |> assign(:participation, participation)
           |> load_instruction_or_tasks()
           |> push_event("scroll_to_top", %{})}

        {:error, reason} ->
          {:noreply, assign_error(socket, reason)}
      end
    end
  end

  def handle_event("next_instruction", _params, socket), do: {:noreply, socket}

  def handle_event("previous_instruction", _params, %{assigns: %{state: :instructions}} = socket) do
    {:noreply,
     update(socket, :instruction_review_index, fn
       index when index > 1 -> index - 1
       index -> index
     end)}
  end

  def handle_event("previous_instruction", _params, socket), do: {:noreply, socket}

  def handle_event(
        "open_detailed_instructions",
        %{"question_key" => question_key},
        %{assigns: %{state: :task, active_question_key: question_key}} = socket
      ) do
    case question_by_key(socket.assigns.questions, question_key) do
      %{module: question} ->
        if function_exported?(question, :detailed_instructions, 1) do
          {:noreply, assign(socket, :detailed_instructions_question_key, question_key)}
        else
          {:noreply, socket}
        end

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("open_detailed_instructions", _params, socket), do: {:noreply, socket}

  def handle_event("close_detailed_instructions", _params, socket) do
    {:noreply, assign(socket, :detailed_instructions_question_key, nil)}
  end

  def handle_event(
        "open_question",
        %{"position" => submitted_position, "question_key" => question_key},
        %{assigns: %{state: :task}} = socket
      ) do
    with {position, ""} <- Integer.parse(submitted_position),
         true <- position == socket.assigns.task.position,
         %{response: response} when not is_nil(response) <-
           question_by_key(socket.assigns.questions, question_key) do
      {:noreply, assign(socket, :active_question_key, question_key)}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("open_question", _params, socket), do: {:noreply, socket}

  def handle_event("previous", _params, %{assigns: %{state: :task}} = socket) do
    previous_position = socket.assigns.task.position - 1

    if previous_position > 0 do
      {:noreply,
       socket
       |> assign(:navigation_mode, :review)
       |> load_task(previous_position, :first_answered)}
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
        id="participant-telemetry"
        phx-hook=".ParticipantTelemetry"
        data-participation-id={@participation && @participation.id}
        data-task-id={if(@state == :task, do: @task && @task.id)}
        data-question-key={if(@state == :task, do: @active_question_key)}
        data-instructions-key={if(@state == :instructions, do: @participation.instructions_key)}
        data-instruction-page-key={
          if(@state == :instructions,
            do: instruction_page_module(@instruction_page, @instruction_review_index).key()
          )
        }
        data-instruction-page-number={if(@state == :instructions, do: @instruction_review_index)}
      >
        <div
          id="participant-shortcuts"
          phx-hook=".KeyboardShortcuts"
          class="mx-auto w-full max-w-5xl"
        >
          <%= case @state do %>
            <% :consent -> %>
              <.consent_panel consent={@consent} launch_token={@launch_token} />
            <% :instructions -> %>
              <.instructions_panel
                page={@instruction_page}
                review_index={@instruction_review_index}
              />
            <% :task -> %>
              <.task_panel
                task={@task}
                questionnaire={@questionnaire}
                questions={@questions}
                active_question_key={@active_question_key}
                detailed_instructions_question_key={@detailed_instructions_question_key}
                total_tasks={@total_tasks}
                navigation_mode={@navigation_mode}
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
                  href={~p"/participate/#{@launch_token}/complete"}
                  rel="noreferrer"
                  data-shortcut="Enter,space"
                  aria-keyshortcuts="Enter Space"
                  class="inline-flex items-center gap-3 rounded-xl bg-indigo-700 px-5 py-3 font-semibold text-white shadow-lg shadow-indigo-900/15 transition hover:-translate-y-0.5 hover:bg-indigo-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900"
                >
                  <.flow_shortcuts /> Continue to Prolific
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
                  aria-keyshortcuts="Enter Space"
                  class="inline-flex items-center gap-3 rounded-xl bg-slate-900 px-5 py-3 font-semibold text-white transition hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900"
                >
                  <.flow_shortcuts /> Open Prolific submissions
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
                  aria-keyshortcuts="Enter Space"
                  class="inline-flex items-center gap-3 rounded-xl bg-slate-900 px-5 py-3 font-semibold text-white transition hover:bg-slate-700 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900"
                >
                  <.flow_shortcuts /> Open Prolific submissions
                </a>
              </.status_panel>
            <% _loading -> %>
              <div
                id="participant-loading"
                class="py-20 text-center text-slate-500 dark:text-slate-400"
              >
                Loading study...
              </div>
          <% end %>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".KeyboardShortcuts">
            export default {
              mounted() {
                this.pending = false
                this.handleEvent("scroll_to_top", () => {
                  window.scrollTo({top: 0, behavior: "smooth"})
                })
                this.handleEvent("scroll_to_question", ({id}) => {
                  window.requestAnimationFrame(() => {
                    const question = document.getElementById(id)
                    if (!question) return

                    const margin = 16
                    const bounds = question.getBoundingClientRect()
                    const fullyVisible = bounds.top >= margin && bounds.bottom <= window.innerHeight - margin
                    if (fullyVisible) return

                    window.scrollTo({
                      top: Math.max(0, window.scrollY + bounds.top - margin),
                      behavior: "smooth"
                    })
                  })
                })
                this.onKeydown = event => {
                  if (this.pending || event.repeat || event.metaKey || event.ctrlKey || event.altKey) return
                  if (this.el.querySelector('[aria-modal="true"]')) return
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

        <script :type={Phoenix.LiveView.ColocatedHook} name=".ParticipantTelemetry">
          export default {
            mounted() {
              this.sessionKey = "participant-telemetry.client-session-id.v1"
              this.sequenceKey = "participant-telemetry.sequence.v1"
              this.clientSessionId = this.read(this.sessionKey) || this.uuid()
              this.write(this.sessionKey, this.clientSessionId)
              this.sequence = Number.parseInt(this.read(this.sequenceKey) || "0", 10) || 0
              this.queue = []
              this.queueKey = null
              this.inFlight = false
              this.lastRender = null
              this.exposure = null
              this.visible = document.visibilityState === "visible"
              this.focused = document.hasFocus()

              this.onVisibilityChange = () => {
                this.accountExposure()
                this.visible = document.visibilityState === "visible"
                this.focused = this.visible && document.hasFocus()
                this.emit(this.visible ? "visibility_visible" : "visibility_hidden")
                if (!this.visible) this.flush()
              }
              this.onFocus = () => {
                this.accountExposure()
                this.focused = true
                this.emit("window_focused")
              }
              this.onBlur = () => {
                this.accountExposure()
                this.focused = false
                this.emit("window_blurred")
              }
              this.onCopy = event => {
                const target = event.target.closest?.("[data-copy-target]")
                if (target && this.el.contains(target)) {
                  this.emit("copy", {target: target.dataset.copyTarget})
                }
              }

              document.addEventListener("visibilitychange", this.onVisibilityChange)
              window.addEventListener("focus", this.onFocus)
              window.addEventListener("blur", this.onBlur)
              this.el.addEventListener("copy", this.onCopy)
              this.flushTimer = window.setInterval(() => this.flush(), 1500)
              this.activateParticipation()
              this.scheduleRenderCheck()
            },
            updated() {
              this.activateParticipation()
              this.scheduleRenderCheck()
            },
            destroyed() {
              this.finishExposure("page_unloaded")
              this.persistQueue()
              document.removeEventListener("visibilitychange", this.onVisibilityChange)
              window.removeEventListener("focus", this.onFocus)
              window.removeEventListener("blur", this.onBlur)
              this.el.removeEventListener("copy", this.onCopy)
              window.clearInterval(this.flushTimer)
              window.clearTimeout(this.retryTimer)
              window.cancelAnimationFrame(this.renderFrame)
            },
            activateParticipation() {
              const participationId = this.el.dataset.participationId
              if (!participationId || this.queueKey) return

              this.queueKey = `participant-telemetry.queue.v1.${participationId}`
              try {
                const stored = JSON.parse(this.read(this.queueKey) || "[]")
                this.queue = Array.isArray(stored) ? stored : []
              } catch (_error) {
                this.queue = []
              }

              const contextKey = `participant-telemetry.context.v1.${participationId}`
              if (!this.read(contextKey)) {
                this.emit("client_context", this.clientContext(), {taskId: null, questionKey: null})
                this.write(contextKey, "1")
              }
              this.flush()
            },
            scheduleRenderCheck() {
              window.cancelAnimationFrame(this.renderFrame)
              this.renderFrame = window.requestAnimationFrame(() => this.detectRender())
            },
            detectRender() {
              if (!this.queueKey) return

              const taskId = this.el.dataset.taskId || null
              const questionKey = this.el.dataset.questionKey || null
              const instructionsKey = this.el.dataset.instructionsKey || null
              const instructionPageKey = this.el.dataset.instructionPageKey || null
              const instructionPageNumber = Number.parseInt(this.el.dataset.instructionPageNumber || "", 10) || null
              const renderKey = `${taskId || ""}:${questionKey || ""}:${instructionsKey || ""}:${instructionPageKey || ""}`
              if (renderKey === this.lastRender) return

              const reason = instructionsKey || this.lastInstructionsKey ? "instruction_changed" :
                (this.lastTaskId && taskId !== this.lastTaskId ? "task_changed" : "question_changed")
              this.finishExposure(reason)
              const previousTaskId = this.lastTaskId
              this.lastRender = renderKey
              this.lastTaskId = taskId
              this.lastInstructionsKey = instructionsKey
              if (taskId && taskId !== previousTaskId) this.emit("task_rendered", {}, {taskId, questionKey: null})
              if (taskId && questionKey) {
                this.emit("question_rendered", {}, {taskId, questionKey})
                this.exposure = {
                  kind: "question",
                  taskId,
                  questionKey,
                  measuredAt: performance.now(),
                  totalMs: 0,
                  visibleMs: 0,
                  focusedMs: 0
                }
              }
              if (instructionsKey && instructionPageKey && instructionPageNumber) {
                const metadata = {
                  instructions_key: instructionsKey,
                  page_key: instructionPageKey,
                  page_number: instructionPageNumber
                }
                this.emit("instruction_rendered", metadata, {taskId: null, questionKey: null})
                this.exposure = {
                  kind: "instruction",
                  ...metadata,
                  measuredAt: performance.now(),
                  totalMs: 0,
                  visibleMs: 0,
                  focusedMs: 0
                }
              }
            },
            accountExposure() {
              if (!this.exposure) return
              const now = performance.now()
              const elapsed = Math.max(0, now - this.exposure.measuredAt)
              this.exposure.totalMs += elapsed
              if (this.visible) this.exposure.visibleMs += elapsed
              if (this.visible && this.focused) this.exposure.focusedMs += elapsed
              this.exposure.measuredAt = now
            },
            finishExposure(reason = "page_unloaded") {
              if (!this.exposure) return
              this.accountExposure()
              const exposure = this.exposure
              this.exposure = null
              if (exposure.kind === "instruction") {
                this.emit("instruction_exposure", {
                  instructions_key: exposure.instructions_key,
                  page_key: exposure.page_key,
                  page_number: exposure.page_number,
                  reason,
                  visible_ms: Math.round(exposure.visibleMs),
                  focused_ms: Math.round(exposure.focusedMs)
                }, {taskId: null, questionKey: null, durationMs: Math.round(exposure.totalMs)})
              } else {
                this.emit("question_exposure", {
                  reason,
                  visible_ms: Math.round(exposure.visibleMs),
                  focused_ms: Math.round(exposure.focusedMs)
                }, {...exposure, durationMs: Math.round(exposure.totalMs)})
              }
            },
            emit(eventType, payload = {}, scope = {}) {
              if (!this.queueKey) return
              this.sequence += 1
              this.write(this.sequenceKey, String(this.sequence))
              this.queue.push({
                event_id: this.uuid(),
                client_session_id: this.clientSessionId,
                sequence: this.sequence,
                kind: eventType,
                client_elapsed_ms: Math.round(performance.now()),
                task_id: scope.taskId === undefined ? (this.el.dataset.taskId || null) : scope.taskId,
                question_key: scope.questionKey === undefined ? (this.el.dataset.questionKey || null) : scope.questionKey,
                duration_ms: scope.durationMs === undefined ? null : scope.durationMs,
                metadata: payload
              })
              this.persistQueue()
              if (this.queue.length >= 20) this.flush()
            },
            flush() {
              if (!this.queueKey || this.inFlight || this.queue.length === 0) return
              const batch = this.queue.slice(0, 20)
              this.inFlight = true
              window.clearTimeout(this.retryTimer)
              this.retryTimer = window.setTimeout(() => {
                this.inFlight = false
              }, 5000)

              this.pushEvent("participant_events", {events: batch}, reply => {
                window.clearTimeout(this.retryTimer)
                const accepted = new Set(Array.isArray(reply?.accepted_ids) ? reply.accepted_ids : [])
                this.queue = this.queue.filter(event => !accepted.has(event.event_id))
                this.inFlight = false
                this.persistQueue()
                if (this.queue.length > 0 && accepted.size > 0) this.flush()
              })
            },
            persistQueue() {
              if (this.queueKey) this.write(this.queueKey, JSON.stringify(this.queue))
            },
            clientContext() {
              const ua = navigator.userAgent
              const browser = ua.match(/(?:Edg|Chrome|Firefox|Version)\/(\d+)/)
              let browserFamily = "other"
              if (/Edg\//.test(ua)) browserFamily = "edge"
              else if (/Firefox\//.test(ua)) browserFamily = "firefox"
              else if (/Chrome\//.test(ua)) browserFamily = "chrome"
              else if (/Safari\//.test(ua)) browserFamily = "safari"

              let osFamily = "other"
              if (/Android/.test(ua)) osFamily = "android"
              else if (/iPhone|iPad|iPod/.test(ua)) osFamily = "ios"
              else if (/Windows/.test(ua)) osFamily = "windows"
              else if (/Mac OS/.test(ua)) osFamily = "macos"
              else if (/Linux/.test(ua)) osFamily = "linux"

              const width = window.innerWidth
              const touchCapable = navigator.maxTouchPoints > 0
              return {
                device_class: width < 640 ? "mobile" : (width < 1024 && touchCapable ? "tablet" : "desktop"),
                viewport_bucket: width < 640 ? "small" : (width < 1024 ? "medium" : "large"),
                touch_capable: touchCapable,
                browser_family: browserFamily,
                browser_major: browser ? Number.parseInt(browser[1], 10) : null,
                os_family: osFamily
              }
            },
            uuid() {
              if (crypto.randomUUID) return crypto.randomUUID()
              const bytes = crypto.getRandomValues(new Uint8Array(16))
              bytes[6] = (bytes[6] & 15) | 64
              bytes[8] = (bytes[8] & 63) | 128
              return [...bytes].map((byte, index) =>
                `${[4, 6, 8, 10].includes(index) ? "-" : ""}${byte.toString(16).padStart(2, "0")}`
              ).join("")
            },
            read(key) {
              try { return sessionStorage.getItem(key) } catch (_error) { return null }
            },
            write(key, value) {
              try { sessionStorage.setItem(key, value) } catch (_error) {}
            }
          }
        </script>
      </div>
    </Layouts.app>
    """
  end

  attr :consent, :any, required: true
  attr :launch_token, :string, required: true

  defp consent_panel(assigns) do
    ~H"""
    <section
      id="consent-panel"
      class="mx-auto max-w-3xl overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-xl shadow-slate-900/5 transition-colors dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/20 sm:rounded-3xl"
    >
      <div class="p-4 sm:p-11">
        {render_definition(@consent)}
      </div>
      <div class="flex flex-col-reverse gap-1.5 border-t border-slate-200 bg-slate-50 px-4 py-3 transition-colors dark:border-slate-700 dark:bg-slate-950/50 sm:flex-row sm:items-center sm:justify-between sm:gap-3 sm:px-11 sm:py-6">
        <.link
          id="decline-consent"
          href={~p"/participate/#{@launch_token}/decline"}
          method="delete"
          class="inline-flex items-center justify-start gap-2 rounded-xl px-3 py-2.5 text-left font-medium text-slate-600 transition hover:bg-slate-200 hover:text-slate-900 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-white sm:px-4 sm:py-3"
        >
          I do not consent
        </.link>
        <button
          id="accept-consent"
          type="button"
          phx-click="accept_consent"
          phx-disable-with="Starting..."
          data-shortcut="Enter,space"
          aria-keyshortcuts="Enter Space"
          class="inline-flex items-center justify-start gap-2.5 rounded-xl bg-indigo-700 px-3 py-2.5 text-left font-semibold text-white shadow-lg shadow-indigo-900/15 transition hover:-translate-y-0.5 hover:bg-indigo-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900 sm:gap-3 sm:px-5 sm:py-3"
        >
          <.flow_shortcuts /> I consent and want to begin
        </button>
      </div>
    </section>
    """
  end

  attr :page, :map, required: true
  attr :review_index, :integer, required: true

  defp instructions_panel(assigns) do
    page_module = Enum.at(assigns.page.pages, assigns.review_index - 1)

    assigns =
      assigns
      |> assign(:page_module, page_module)
      |> assign(:at_frontier?, assigns.review_index == assigns.page.page_number)

    ~H"""
    <section id="instructions-panel" class="mx-auto max-w-3xl space-y-3 sm:space-y-6">
      <header id="instruction-progress" class="flex items-center justify-between gap-4">
        <p class="text-xs font-bold uppercase tracking-[0.14em] text-indigo-700 dark:text-indigo-300 sm:text-sm">
          Getting started
        </p>
        <p class="text-xs font-semibold tabular-nums text-slate-600 dark:text-slate-300 sm:text-sm">
          Page {@review_index} / {@page.total_pages}
        </p>
      </header>

      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-xl shadow-slate-900/5 transition-colors dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/20 sm:rounded-3xl sm:p-11">
        {render_instruction_definition(@page_module)}
      </div>

      <footer class="flex items-center justify-between gap-4">
        <button
          id="previous-instruction"
          type="button"
          phx-click="previous_instruction"
          disabled={@review_index == 1}
          class="inline-flex items-center gap-2 rounded-xl px-3 py-2 font-semibold text-slate-600 transition hover:bg-white hover:text-slate-950 disabled:cursor-not-allowed disabled:opacity-30 dark:text-slate-300 dark:hover:bg-slate-800 dark:hover:text-white sm:px-4 sm:py-2.5"
        >
          <.icon name="hero-arrow-left" class="size-4" /> Previous
        </button>
        <button
          id="next-instruction"
          type="button"
          phx-click="next_instruction"
          data-frontier={to_string(@at_frontier?)}
          class="inline-flex items-center gap-2 rounded-xl bg-indigo-700 px-4 py-2.5 font-semibold text-white shadow-lg shadow-indigo-900/15 transition hover:-translate-y-0.5 hover:bg-indigo-600 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:bg-indigo-600 dark:hover:bg-indigo-500 dark:focus:ring-offset-slate-900 sm:px-5 sm:py-3"
        >
          Next <.icon name="hero-arrow-right" class="size-4" />
        </button>
      </footer>
    </section>
    """
  end

  attr :task, :any, required: true
  attr :questionnaire, :any, required: true
  attr :questions, :list, required: true
  attr :active_question_key, :string, default: nil
  attr :detailed_instructions_question_key, :string, default: nil
  attr :total_tasks, :integer, required: true
  attr :navigation_mode, :atom, required: true

  defp task_panel(assigns) do
    progress = round((assigns.task.position - 1) / assigns.total_tasks * 100)
    assigns = assign(assigns, :progress, progress)

    ~H"""
    <section
      id="task-panel"
      data-task-id={@task.id}
      data-navigation-mode={@navigation_mode}
      class="space-y-3 sm:space-y-6"
    >
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

      <div class="rounded-2xl border border-slate-200 bg-white p-2 shadow-xl shadow-slate-900/5 transition-colors dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/20 sm:rounded-3xl sm:p-9">
        <%= if @questionnaire.task_type() == :comparison do %>
          <div class="grid gap-2 md:grid-cols-2 md:gap-4" id="comparison-posts">
            <.post_card
              id="post-a"
              copy_target="post_a"
              label="Post A"
              text={@task.stimuli["post_a"]["text"]}
            />
            <.post_card
              id="post-b"
              copy_target="post_b"
              label="Post B"
              text={@task.stimuli["post_b"]["text"]}
            />
          </div>
        <% else %>
          <article
            id="single-post"
            data-copy-target="post"
            class="rounded-xl border border-slate-200 bg-slate-50 p-3 transition-colors dark:border-slate-700 dark:bg-slate-950/60 sm:rounded-2xl sm:p-8"
          >
            <p class="whitespace-pre-wrap break-words text-base leading-7 text-slate-800 dark:text-slate-100 sm:text-lg">
              {@task.stimuli["post"]["text"]}
            </p>
          </article>
        <% end %>

        <div id="questionnaire-accordion" class="mt-3 space-y-1.5 sm:mt-6 sm:space-y-3">
          <.question_item
            :for={question <- @questions}
            task={@task}
            questionnaire={@questionnaire}
            question={question}
            active?={question.key == @active_question_key}
            details_open?={question.key == @detailed_instructions_question_key}
          />
        </div>
      </div>

      <footer class="flex items-center justify-between gap-4">
        <button
          id="previous-task"
          type="button"
          phx-click="previous"
          data-shortcut="z"
          aria-keyshortcuts="Z"
          disabled={@task.position == 1}
          class="inline-flex items-center gap-2 rounded-xl px-3 py-2 font-medium text-slate-600 transition hover:bg-white hover:text-slate-950 disabled:cursor-not-allowed disabled:opacity-30 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-white sm:px-4 sm:py-2.5"
        >
          <.shortcut_key>Z</.shortcut_key>
          Previous
        </button>
        <p class="hidden text-right text-xs leading-5 text-slate-500 dark:text-slate-400 sm:block sm:text-sm">
          Click an answer or use its keyboard shortcut
        </p>
      </footer>
    </section>
    """
  end

  attr :task, :any, required: true
  attr :questionnaire, :any, required: true
  attr :question, :map, required: true
  attr :active?, :boolean, required: true
  attr :details_open?, :boolean, required: true

  defp question_item(assigns) do
    locked? = is_nil(assigns.question.response) and not assigns.active?

    assigns =
      assigns
      |> assign(:locked?, locked?)
      |> assign(:answered?, not is_nil(assigns.question.response))

    ~H"""
    <section
      id={"question-#{@question.number}"}
      data-question-key={@question.key}
      data-state={question_state(@active?, @answered?)}
      class={[
        "scroll-m-4 overflow-hidden rounded-2xl border transition duration-300",
        @active? &&
          "border-indigo-400 bg-indigo-50/70 shadow-md shadow-indigo-950/5 dark:border-indigo-500 dark:bg-indigo-500/10 dark:shadow-black/20",
        @answered? && not @active? &&
          "border-slate-200/60 bg-slate-50/40 opacity-50 hover:opacity-75 dark:border-slate-800 dark:bg-slate-950/30",
        @locked? &&
          "border-slate-200/50 bg-slate-100/40 opacity-25 dark:border-slate-800/70 dark:bg-slate-950/20"
      ]}
    >
      <button
        id={"question-#{@question.number}-header"}
        type="button"
        phx-click="open_question"
        phx-value-position={@task.position}
        phx-value-question_key={@question.key}
        aria-expanded={to_string(@active?)}
        aria-controls={"question-#{@question.number}-region"}
        disabled={@locked? or @active?}
        class={[
          "flex w-full items-center text-left disabled:cursor-default",
          @active? && "gap-2.5 px-3 py-2.5 sm:gap-4 sm:px-6 sm:py-4",
          not @active? && "gap-2 px-3 py-1.5 sm:gap-3 sm:px-5 sm:py-2"
        ]}
      >
        <span class={[
          "flex shrink-0 items-center justify-center rounded-full font-bold",
          @active? &&
            "size-7 bg-indigo-700 text-xs text-white dark:bg-indigo-500 sm:size-8 sm:text-sm",
          not @active? &&
            "size-6 bg-slate-100 text-[10px] text-slate-400 dark:bg-slate-800/70 dark:text-slate-500 sm:size-7 sm:text-xs"
        ]}>
          {@question.number}
        </span>
        <span class="min-w-0 flex-1">
          <span class={[
            "font-bold uppercase tracking-[0.14em] text-indigo-600 dark:text-indigo-300",
            @active? && "block text-[10px] sm:text-xs",
            not @active? && "hidden"
          ]}>
            Question {@question.number}
          </span>
          <span class={[
            "block",
            @active? && "mt-1",
            not @active? && "[&>span]:text-sm [&>span]:leading-5 sm:[&>span]:text-base"
          ]}>
            {render_definition(@question.module)}
          </span>
        </span>
        <span
          :if={@answered?}
          class="hidden text-sm font-medium text-indigo-700 dark:text-indigo-300 sm:block"
        >
          {answer_summary(@question.response.choice)}
        </span>
        <span
          :if={@locked?}
          class="hidden text-xs font-semibold uppercase tracking-wider text-slate-500 sm:block"
        >
          Locked
        </span>
      </button>

      <div class={if(@active?, do: "grid grid-rows-[1fr]", else: "grid grid-rows-[0fr]") <> " transition-[grid-template-rows] duration-300"}>
        <div class="overflow-hidden">
          <div
            id={"question-#{@question.number}-region"}
            data-copy-target="question"
            data-question-key={@question.key}
            role="region"
            aria-labelledby={"question-#{@question.number}-header"}
            class="border-t border-indigo-200 px-3 py-3 dark:border-indigo-500/30 sm:px-6 sm:py-6"
          >
            <%= if @active? do %>
              <div class="flex flex-wrap items-baseline gap-x-2 gap-y-1 text-sm leading-6 text-slate-600 dark:text-slate-300 sm:text-base">
                <p>{@question.module.description()}</p>
                <button
                  :if={function_exported?(@question.module, :detailed_instructions, 1)}
                  id={"question-#{@question.number}-detailed-instructions"}
                  type="button"
                  phx-click="open_detailed_instructions"
                  phx-value-question_key={@question.key}
                  class="inline-flex shrink-0 items-center gap-1 font-semibold text-indigo-700 underline decoration-indigo-300 underline-offset-4 transition hover:text-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:text-indigo-300 dark:decoration-indigo-600 dark:hover:text-indigo-200 dark:focus:ring-offset-slate-900"
                >
                  Detailed instructions <.icon name="hero-arrow-up-right" class="size-3.5" />
                </button>
              </div>

              <.detailed_instructions_dialog
                :if={@details_open?}
                question={@question}
              />

              <%= if @questionnaire.task_type() == :comparison do %>
                <.comparison_actions task={@task} question={@question} />
              <% else %>
                <.binary_actions task={@task} question={@question} />
              <% end %>
            <% end %>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :question, :map, required: true

  defp detailed_instructions_dialog(assigns) do
    ~H"""
    <div
      id="detailed-instructions-dialog"
      class="fixed inset-0 z-50 grid place-items-center p-3 sm:p-6"
      phx-window-keydown="close_detailed_instructions"
      phx-key="escape"
    >
      <button
        id="detailed-instructions-backdrop"
        type="button"
        phx-click="close_detailed_instructions"
        aria-label="Close detailed instructions"
        class="absolute inset-0 bg-slate-950/60 backdrop-blur-sm"
      />
      <section
        role="dialog"
        aria-modal="true"
        aria-labelledby="detailed-instructions-title"
        tabindex="-1"
        phx-mounted={JS.focus()}
        class="relative z-10 max-h-[min(40rem,calc(100vh-1.5rem))] w-full max-w-2xl overflow-y-auto rounded-2xl border border-slate-200 bg-white p-5 shadow-2xl focus:outline-none dark:border-slate-700 dark:bg-slate-900 sm:p-8"
      >
        <header class="flex items-start justify-between gap-4 border-b border-slate-200 pb-4 dark:border-slate-700">
          <div>
            <p class="text-xs font-bold uppercase tracking-[0.14em] text-indigo-600 dark:text-indigo-300">
              Question {@question.number}
            </p>
            <h2
              id="detailed-instructions-title"
              class="mt-1 text-xl font-bold tracking-tight text-slate-950 dark:text-white"
            >
              Detailed instructions
            </h2>
          </div>
          <button
            id="close-detailed-instructions"
            type="button"
            phx-click="close_detailed_instructions"
            aria-label="Close detailed instructions"
            class="inline-flex size-9 shrink-0 items-center justify-center rounded-lg text-slate-500 transition hover:bg-slate-100 hover:text-slate-950 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:hover:bg-slate-800 dark:hover:text-white"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </header>
        <div
          id="detailed-instructions-question"
          class="mt-5 rounded-xl border border-indigo-200 bg-indigo-50/70 p-4 dark:border-indigo-500/30 dark:bg-indigo-500/10"
        >
          {render_definition(@question.module, %{id: "detailed-instructions-question-text"})}
        </div>
        <div class="mt-5">{render_detailed_instructions(@question.module)}</div>
      </section>
    </div>
    """
  end

  attr :task, :any, required: true
  attr :question, :map, required: true

  defp comparison_actions(assigns) do
    ~H"""
    <div id="comparison-answer-options" class="mt-3 grid gap-1.5 sm:mt-5 sm:grid-cols-3 sm:gap-3">
      <.compact_choice
        id="answer-post-a"
        label="Post A"
        shortcut="A"
        choice="post_a"
        position={@task.position}
        question_key={@question.key}
        selected={selected?(@question.response, :post_a)}
      />
      <.compact_choice
        id="answer-equal"
        label="Very close / neither"
        shortcut="S"
        choice="equal"
        position={@task.position}
        question_key={@question.key}
        selected={selected?(@question.response, :equal)}
      />
      <.compact_choice
        id="answer-post-b"
        label="Post B"
        shortcut="D"
        choice="post_b"
        position={@task.position}
        question_key={@question.key}
        selected={selected?(@question.response, :post_b)}
      />
    </div>
    <div
      id="comparison-skip"
      class="mt-3 flex justify-end border-t border-slate-200 pt-2 dark:border-slate-700 sm:mt-6 sm:pt-4"
    >
      <.skip_choice
        position={@task.position}
        question_key={@question.key}
        selected={selected?(@question.response, :skip)}
      />
    </div>
    """
  end

  attr :task, :any, required: true
  attr :question, :map, required: true

  defp binary_actions(assigns) do
    ~H"""
    <div id="binary-answer-options" class="mt-3 grid gap-1.5 sm:mt-5 sm:grid-cols-2 sm:gap-3">
      <.compact_choice
        id="answer-yes"
        label="Yes"
        shortcut="A"
        choice="yes"
        position={@task.position}
        question_key={@question.key}
        selected={selected?(@question.response, :yes)}
      />
      <.compact_choice
        id="answer-no"
        label="No"
        shortcut="S"
        choice="no"
        position={@task.position}
        question_key={@question.key}
        selected={selected?(@question.response, :no)}
      />
    </div>
    <div
      id="binary-skip"
      class="mt-3 flex justify-end border-t border-slate-200 pt-2 dark:border-slate-700 sm:mt-6 sm:pt-4"
    >
      <.skip_choice
        position={@task.position}
        question_key={@question.key}
        selected={selected?(@question.response, :skip)}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :copy_target, :string, required: true
  attr :label, :string, required: true
  attr :text, :string, required: true

  defp post_card(assigns) do
    ~H"""
    <article
      id={@id}
      data-copy-target={@copy_target}
      class="flex min-h-0 flex-col overflow-hidden rounded-xl border border-slate-200 bg-slate-50 transition-colors dark:border-slate-700 dark:bg-slate-950/60 sm:rounded-2xl md:min-h-56"
    >
      <span class="border-b border-slate-200 px-3 py-2 text-xs font-bold uppercase tracking-[0.14em] text-indigo-700 dark:border-slate-700 dark:text-indigo-300 sm:px-7 sm:py-3">
        {@label}
      </span>
      <span class="flex-1 whitespace-pre-wrap break-words p-3 text-base leading-6 text-slate-800 dark:text-slate-100 sm:p-7 sm:text-lg sm:leading-7">
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
  attr :question_key, :string, required: true
  attr :selected, :boolean, default: false

  defp compact_choice(assigns) do
    ~H"""
    <button
      id={@id}
      type="button"
      phx-click="answer"
      phx-value-choice={@choice}
      phx-value-position={@position}
      phx-value-question_key={@question_key}
      data-shortcut={String.downcase(@shortcut)}
      aria-keyshortcuts={@shortcut}
      aria-pressed={to_string(@selected)}
      class={[
        "inline-flex items-center justify-start gap-2 rounded-xl border px-3 py-2.5 text-left font-semibold transition focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 dark:focus:ring-offset-slate-900 sm:gap-3 sm:px-5 sm:py-3.5",
        @selected &&
          "border-indigo-600 bg-indigo-700 text-white dark:border-indigo-400 dark:bg-indigo-500/30",
        not @selected &&
          "border-slate-300 bg-white text-slate-800 hover:border-indigo-400 hover:bg-indigo-50 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:hover:border-indigo-400 dark:hover:bg-indigo-500/15 dark:focus:ring-offset-slate-900"
      ]}
    >
      <.shortcut_key>{@shortcut}</.shortcut_key>
      {@label}
    </button>
    """
  end

  attr :position, :integer, required: true
  attr :question_key, :string, required: true
  attr :selected, :boolean, default: false

  defp skip_choice(assigns) do
    ~H"""
    <button
      id="answer-skip"
      type="button"
      phx-click="answer"
      phx-value-choice="skip"
      phx-value-position={@position}
      phx-value-question_key={@question_key}
      data-shortcut="x"
      aria-keyshortcuts="X"
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
      <.shortcut_key>X</.shortcut_key>
      Skip this task
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
      class="mx-auto max-w-xl rounded-2xl border border-slate-200 bg-white p-4 shadow-xl shadow-slate-900/5 transition-colors dark:border-slate-700 dark:bg-slate-900 dark:shadow-black/20 sm:rounded-3xl sm:p-12"
    >
      <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700 dark:text-indigo-300">
        {@eyebrow}
      </p>
      <h1 class="mt-3 text-2xl font-semibold tracking-tight text-slate-950 dark:text-white sm:text-3xl">
        {@title}
      </h1>
      <p class="mt-5 leading-7 text-slate-600 dark:text-slate-300">{@message}</p>
      <div class="mt-6 sm:mt-8">{render_slot(@inner_block)}</div>
    </section>
    """
  end

  slot :inner_block, required: true

  defp shortcut_key(assigns) do
    ~H"""
    <kbd
      aria-hidden="true"
      class="inline-flex min-w-5 items-center justify-center rounded border border-slate-600 bg-white px-1 font-mono text-[10px] font-bold leading-4 text-slate-950 shadow-[0_1px_0_#475569] dark:border-slate-300 dark:bg-slate-950 dark:text-white dark:shadow-[0_1px_0_#cbd5e1]"
    >
      {render_slot(@inner_block)}
    </kbd>
    """
  end

  defp flow_shortcuts(assigns) do
    ~H"""
    <span class="inline-flex shrink-0 items-center gap-1">
      <.shortcut_key>Enter</.shortcut_key>
      <span class="text-[10px] font-medium opacity-70">or</span>
      <.shortcut_key>Space</.shortcut_key>
    </span>
    """
  end

  defp load_launch(socket, launch_token) do
    with {:ok, context} <- DataCollection.resolve_participant_launch(launch_token),
         %Condition{} = condition <- context.condition do
      participant_context = participant_attrs(context.launch)

      socket =
        socket
        |> assign(:condition, condition)
        |> assign(:participant_context, participant_context)

      case context.participation do
        %Participation{} = participation -> load_participation(socket, participation)
        nil -> load_consent(socket, condition)
      end
    else
      _other -> assign_error(socket, :invalid_launch)
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
    socket
    |> assign(:participation, participation)
    |> load_instruction_or_tasks()
  end

  defp load_instruction_or_tasks(socket) do
    participation = socket.assigns.participation

    case DataCollection.instruction_page(participation) do
      {:ok, :complete} -> load_tasks(socket)
      {:ok, page} -> load_instruction_page(socket, participation, page)
      {:error, reason} -> assign_error(socket, reason)
    end
  end

  defp load_instruction_page(socket, _participation, page) do
    instruction_page = Map.put(page, :pages, page.instruction_set.pages())

    socket
    |> assign(:instruction_page, instruction_page)
    |> assign(:instruction_review_index, page.page_number)
    |> assign(:state, :instructions)
  end

  defp load_tasks(socket) do
    participation = socket.assigns.participation

    case DataCollection.next_incomplete_task(participation) do
      nil ->
        case DataCollection.complete_participation(participation) do
          {:ok, completed} -> socket |> assign(:participation, completed) |> load_completed()
          {:error, reason} -> assign_error(socket, reason)
        end

      task ->
        socket
        |> assign(:navigation_mode, :forward)
        |> assign(:frontier_position, task.position)
        |> load_task(task.position)
    end
  end

  defp load_task(socket, position, active \\ :next_unanswered) do
    case DataCollection.task_page(socket.assigns.participation, position) do
      {:ok, page} ->
        active_question_key = active_question_key(page, active)

        socket
        |> assign(:task, page.task)
        |> assign(:questionnaire, page.questionnaire)
        |> assign(:questions, page.questions)
        |> assign(:active_question_key, active_question_key)
        |> assign(:detailed_instructions_question_key, nil)
        |> assign(:total_tasks, page.total_tasks)
        |> assign(:state, :task)

      {:error, reason} ->
        assign_error(socket, reason)
    end
  end

  defp after_answer(%{assigns: %{navigation_mode: :review}} = socket) do
    case DataCollection.task_page(socket.assigns.participation, socket.assigns.task.position) do
      {:ok, page} -> advance_review(socket, page)
      {:error, reason} -> {:noreply, assign_error(socket, reason)}
    end
  end

  defp after_answer(socket) do
    case DataCollection.task_page(socket.assigns.participation, socket.assigns.task.position) do
      {:ok, %{complete?: false} = page} ->
        {:noreply,
         socket
         |> assign_page(page, page.active_question_key)
         |> scroll_to_question(page, page.active_question_key)}

      {:ok, %{complete?: true}} ->
        if socket.assigns.task.position < socket.assigns.total_tasks do
          next_position = socket.assigns.task.position + 1

          {:noreply,
           socket
           |> assign(:frontier_position, next_position)
           |> load_task(next_position)
           |> push_event("scroll_to_top", %{})}
        else
          complete_and_redirect(socket)
        end

      {:error, reason} ->
        {:noreply, assign_error(socket, reason)}
    end
  end

  defp advance_review(socket, page) do
    current_index =
      Enum.find_index(page.questions, &(&1.key == socket.assigns.active_question_key))

    next_question = current_index && Enum.at(page.questions, current_index + 1)

    cond do
      next_question ->
        {:noreply,
         socket
         |> assign_page(page, next_question.key)
         |> scroll_to_question(page, next_question.key)}

      socket.assigns.task.position + 1 < socket.assigns.frontier_position ->
        {:noreply,
         socket
         |> load_task(socket.assigns.task.position + 1, :first_answered)
         |> push_event("scroll_to_top", %{})}

      true ->
        {:noreply,
         socket
         |> assign(:navigation_mode, :forward)
         |> load_task(socket.assigns.frontier_position)
         |> push_event("scroll_to_top", %{})}
    end
  end

  defp complete_and_redirect(socket) do
    case DataCollection.complete_participation(socket.assigns.participation) do
      {:ok, completed} ->
        socket = socket |> assign(:participation, completed) |> load_completed()

        {:noreply, redirect(socket, to: ~p"/participate/#{socket.assigns.launch_token}/complete")}

      {:error, reason} ->
        {:noreply, assign_error(socket, reason)}
    end
  end

  defp assign_page(socket, page, active_question_key) do
    socket
    |> assign(:task, page.task)
    |> assign(:questionnaire, page.questionnaire)
    |> assign(:questions, page.questions)
    |> assign(:active_question_key, active_question_key)
    |> assign(:detailed_instructions_question_key, nil)
    |> assign(:total_tasks, page.total_tasks)
    |> assign(:state, :task)
  end

  defp scroll_to_question(socket, page, question_key) do
    case Enum.find(page.questions, &(&1.key == question_key)) do
      nil -> socket
      question -> push_event(socket, "scroll_to_question", %{id: "question-#{question.number}"})
    end
  end

  defp active_question_key(page, :next_unanswered), do: page.active_question_key

  defp active_question_key(page, :first_answered) do
    case Enum.find(page.questions, & &1.response) do
      nil -> page.active_question_key
      question -> question.key
    end
  end

  defp instruction_page_module(page, review_index) do
    Enum.at(page.pages, review_index - 1)
  end

  defp question_by_key(questions, key), do: Enum.find(questions, &(&1.key == key))

  defp question_state(true, _answered?), do: "active"
  defp question_state(false, true), do: "answered"
  defp question_state(false, false), do: "locked"

  defp answer_summary(:post_a), do: "Post A"
  defp answer_summary(:post_b), do: "Post B"
  defp answer_summary(:equal), do: "Very close / neither"
  defp answer_summary(:yes), do: "Yes"
  defp answer_summary(:no), do: "No"
  defp answer_summary(:skip), do: "Skipped"

  defp load_completed(socket), do: assign(socket, :state, :completed)

  defp assign_error(socket, _reason), do: assign(socket, :state, :error)

  defp participant_attrs(launch) do
    %{
      prolific_participant_id: launch.prolific_participant_id,
      prolific_study_id: launch.prolific_study_id,
      prolific_session_id: launch.prolific_session_id
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
  defp render_definition(module, assigns), do: module.render(assigns)
  defp render_instruction_definition(module), do: module.render(%{instruction_page: true})
  defp render_detailed_instructions(module), do: module.detailed_instructions(%{})
end
