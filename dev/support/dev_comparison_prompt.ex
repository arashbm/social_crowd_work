defmodule SocialCrowdWork.DevComparisonPrompt do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "dev-negative-tone.v1"

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dev-comparison-prompt">
      <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700">
        Development prompt
      </p>
      <h1 class="mt-2 text-2xl font-semibold tracking-tight text-slate-950 dark:text-white sm:text-3xl">
        Which post has a more negative tone?
      </h1>
      <p class="mt-3 leading-6 text-slate-600 dark:text-slate-300">
        Consider the overall wording and attitude. Choose equal if neither post is more negative.
      </p>
    </div>
    """
  end
end
