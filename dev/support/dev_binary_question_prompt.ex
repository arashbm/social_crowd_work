defmodule SocialCrowdWork.DevBinaryQuestionPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "dev-expresses-frustration.v1"

  @impl true
  def description, do: "Judge the frustration communicated by the wording in the post."

  @impl true
  def task_type, do: :binary_question

  @impl true
  def choices, do: [:yes, :no, :skip]

  @impl true
  def render(assigns) do
    assigns = Map.put_new(assigns, :id, "dev-binary-question-prompt")

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      Does this post express <u class="decoration-indigo-500 decoration-2 underline-offset-4">frustration</u>?
    </span>
    """
  end
end
