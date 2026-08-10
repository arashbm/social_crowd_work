defmodule SocialCrowdWork.DevBinaryQuestionPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "dev-expresses-frustration.v1"

  @impl true
  def task_type, do: :binary_question

  @impl true
  def choices, do: [:yes, :no, :skip]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dev-binary-question-prompt">
      <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700">
        Development prompt
      </p>
      <h1 class="mt-2 text-2xl font-semibold tracking-tight text-slate-950 dark:text-white sm:text-3xl">
        Does this post express frustration?
      </h1>
      <p class="mt-3 leading-6 text-slate-600 dark:text-slate-300">
        Answer based only on the text shown below.
      </p>
    </div>
    """
  end
end
