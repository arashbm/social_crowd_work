defmodule SocialCrowdWorkWeb.AdminLive.Definitions do
  use SocialCrowdWorkWeb, :live_view

  alias SocialCrowdWork.{Consents, Prompts, Questionnaires}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Definitions")
     |> assign(:prompts, Prompts.all())
     |> assign(:questionnaires, Questionnaires.all())
     |> assign(:consents, Consents.all())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} variant={:admin}>
      <.admin_header
        title="Definitions"
        description="Read-only catalog of code-defined, versioned questionnaires, prompts, and consent documents."
      />

      <section>
        <h2 class="mb-4 text-lg font-semibold text-slate-950 dark:text-white">Questionnaires</h2>
        <.admin_empty
          :if={@questionnaires == []}
          id="questionnaires-empty"
          title="No production questionnaires"
          message="Add a versioned questionnaire before importing production manifests."
        />
        <div id="questionnaire-definitions" class="grid gap-5 xl:grid-cols-2">
          <article
            :for={questionnaire <- @questionnaires}
            id={"questionnaire-#{questionnaire.key()}"}
            class="rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900"
          >
            <div class="flex items-center justify-between gap-4">
              <code class="text-sm font-bold text-indigo-700 dark:text-indigo-300">{questionnaire.key()}</code>
              <span class="text-xs capitalize text-slate-500">{questionnaire.task_type()
              |> Atom.to_string()
              |> String.replace("_", " ")}</span>
            </div>
            <ol class="mt-5 space-y-3">
              <li
                :for={{question, number} <- Enum.with_index(questionnaire.questions(), 1)}
                id={"questionnaire-#{questionnaire.key()}-question-#{number}"}
                class="flex items-center gap-3 rounded-xl border border-slate-200 bg-slate-50 p-3 dark:border-slate-700 dark:bg-slate-950/60"
              >
                <span class="flex size-7 shrink-0 items-center justify-center rounded-lg bg-indigo-100 text-xs font-bold text-indigo-700 dark:bg-indigo-500/20 dark:text-indigo-300">{number}</span>
                <code class="text-xs font-semibold">{question.key()}</code>
              </li>
            </ol>
          </article>
        </div>
      </section>

      <section class="mt-9">
        <h2 class="mb-4 text-lg font-semibold text-slate-950 dark:text-white">Prompts</h2>
        <.admin_empty
          :if={@prompts == []}
          id="prompts-empty"
          title="No production prompts"
          message="Add versioned prompt modules before importing production manifests."
        />
        <div id="prompt-definitions" class="grid gap-5 xl:grid-cols-2">
          <article
            :for={prompt <- @prompts}
            id={"prompt-#{prompt.key()}"}
            class="rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900"
          >
            <div class="mb-5 flex items-center justify-between gap-4">
              <code class="text-sm font-bold text-indigo-700 dark:text-indigo-300">{prompt.key()}</code><span class="text-xs capitalize text-slate-500">{prompt.task_type()
              |> Atom.to_string()
              |> String.replace("_", " ")}</span>
            </div>
            <div class="rounded-xl border border-slate-200 bg-slate-50 p-5 dark:border-slate-700 dark:bg-slate-950/60">
              {render_definition(prompt)}
            </div>
            <p class="mt-4 text-xs text-slate-500">Choices: {Enum.join(prompt.choices(), ", ")}</p>
          </article>
        </div>
      </section>

      <section class="mt-9">
        <h2 class="mb-4 text-lg font-semibold text-slate-950 dark:text-white">Consent documents</h2>
        <.admin_empty
          :if={@consents == []}
          id="consents-empty"
          title="No production consent"
          message="Add a versioned consent module before activating production conditions."
        />
        <div id="consent-definitions" class="grid gap-5 xl:grid-cols-2">
          <article
            :for={consent <- @consents}
            id={"consent-#{consent.key()}"}
            class="rounded-2xl border border-slate-200 bg-white p-6 dark:border-slate-800 dark:bg-slate-900"
          >
            <code class="text-sm font-bold text-indigo-700 dark:text-indigo-300">{consent.key()}</code>
            <div class="mt-5 rounded-xl border border-slate-200 bg-slate-50 p-5 dark:border-slate-700 dark:bg-slate-950/60">
              {render_definition(consent)}
            </div>
          </article>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp render_definition(module), do: module.render(%{})
end
