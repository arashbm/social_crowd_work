defmodule SocialCrowdWork.TestBinaryQuestionPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "test-binary-question.v1"

  @impl true
  def description, do: "Judge the test post against the test criterion."

  @impl true
  def task_type, do: :binary_question

  @impl true
  def choices, do: [:yes, :no, :skip]

  @impl true
  def render(assigns) do
    assigns = Map.put_new(assigns, :id, "test-binary-question-prompt")

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      Does the test post match the <u class="decoration-indigo-500 decoration-2 underline-offset-4">test criterion</u>?
    </span>
    """
  end
end
