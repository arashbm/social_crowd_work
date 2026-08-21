defmodule SocialCrowdWork.TestComparisonPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "test-comparison.v1"

  @impl true
  def description, do: "Compare both test posts against the test criterion."

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    assigns = Map.put_new(assigns, :id, "test-comparison-prompt")

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      Which test post matches the <u class="decoration-indigo-500 decoration-2 underline-offset-4">test criterion</u>?
    </span>
    """
  end

  @impl true
  def detailed_instructions(assigns) do
    ~H"""
    <p id="test-comparison-detailed-instructions">Detailed test comparison guidance.</p>
    """
  end
end
