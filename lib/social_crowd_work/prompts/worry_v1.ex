defmodule SocialCrowdWork.Prompts.WorryV1 do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "worry.v1"

  @impl true
  def title, do: "Which post shows more worry about something bad happening?"

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    ~H"""
    <div id="worry-prompt-v1">
      <h1 class="text-2xl font-semibold leading-tight tracking-tight text-slate-950 dark:text-white sm:text-3xl">
        Which post shows more
        <u class="decoration-indigo-500 decoration-2 underline-offset-4 dark:decoration-indigo-400">worry</u>
        about something bad happening?
      </h1>
    </div>
    """
  end
end
