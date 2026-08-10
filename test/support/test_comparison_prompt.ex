defmodule SocialCrowdWork.TestComparisonPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "test-comparison.v1"

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="test-comparison-prompt">
      <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700">Comparison</p>
      <h1 class="mt-2 text-2xl font-semibold tracking-tight text-slate-950 dark:text-white sm:text-3xl">
        Which test post matches the test criterion?
      </h1>
    </div>
    """
  end
end
