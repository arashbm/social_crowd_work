defmodule SocialCrowdWork.Prompts.WorryV1 do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "worry.v1"

  @impl true
  def description,
    do:
      "Compare how strongly each post expresses worry or anticipation that something bad may happen."

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    assigns = Map.put_new(assigns, :id, "worry-prompt-v1")

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      Which post shows more
      <u class="decoration-indigo-500 decoration-2 underline-offset-4 dark:decoration-indigo-400">worry</u>
      about something bad happening?
    </span>
    """
  end

  @impl true
  def detailed_instructions(assigns) do
    ~H"""
    <div class="space-y-4 text-sm leading-6 text-slate-600 dark:text-slate-300">
      <p>Read both posts in full and compare the degree of worry expressed in each one.</p>
      <p>
        Look for concern, apprehension, or anticipation that an unwanted event may occur. Judge what the text communicates rather than what the writer might feel privately.
      </p>
      <p>
        Choose Post A or Post B when one clearly expresses more worry. Choose Very close / neither when the difference is too small to judge or neither post expresses the criterion.
      </p>
    </div>
    """
  end
end
