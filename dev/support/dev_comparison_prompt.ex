defmodule SocialCrowdWork.DevComparisonPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "dev-negative-tone.v1"

  @impl true
  def description, do: "Compare the overall wording and attitude conveyed by each post."

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    assigns = Map.put_new(assigns, :id, "dev-comparison-prompt")

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      Which post has a more <u class="decoration-indigo-500 decoration-2 underline-offset-4">negative tone</u>?
    </span>
    """
  end
end
