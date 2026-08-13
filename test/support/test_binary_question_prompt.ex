defmodule SocialCrowdWork.TestBinaryQuestionPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "test-binary-question.v1"

  @impl true
  def title, do: "Does the test post match the test criterion?"

  @impl true
  def task_type, do: :binary_question

  @impl true
  def choices, do: [:yes, :no, :skip]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="test-binary-question-prompt">
      <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700">Question</p>
      <h1 class="mt-2 text-2xl font-semibold tracking-tight text-slate-950 dark:text-white sm:text-3xl">
        Does the test post match the test criterion?
      </h1>
    </div>
    """
  end
end
