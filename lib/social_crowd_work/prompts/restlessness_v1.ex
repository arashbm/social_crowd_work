defmodule SocialCrowdWork.Prompts.RestlessnessV1 do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "restlessness.v1"

  @impl true
  def title,
    do: "Which post sounds more emotionally tense, agitated, or unable to settle down?"

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="restlessness-prompt-v1">
      <h1 class="text-2xl font-semibold leading-tight tracking-tight text-slate-950 dark:text-white sm:text-3xl">
        Which post sounds more <u class="decoration-indigo-500 decoration-2 underline-offset-4 dark:decoration-indigo-400">emotionally tense, agitated, or unable to settle down</u>?
      </h1>
    </div>
    """
  end
end
