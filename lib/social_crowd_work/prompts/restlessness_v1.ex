defmodule SocialCrowdWork.Prompts.RestlessnessV1 do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "restlessness.v1"

  @impl true
  def description,
    do:
      "Compare how strongly each post conveys emotional tension, agitation, or difficulty settling down."

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    assigns = Map.put_new(assigns, :id, "restlessness-prompt-v1")

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      Which post sounds more <u class="decoration-indigo-500 decoration-2 underline-offset-4 dark:decoration-indigo-400">emotionally tense, agitated, or unable to settle down</u>?
    </span>
    """
  end

  @impl true
  def detailed_instructions(assigns) do
    ~H"""
    <div class="space-y-4 text-sm leading-6 text-slate-600 dark:text-slate-300">
      <p>
        Read both posts in full and compare the emotional restlessness communicated by their wording.
      </p>
      <p>
        Consider signs of tension, agitation, unease, or an inability to relax or settle. Do not base the decision only on writing style, punctuation, or topic intensity.
      </p>
      <p>
        Choose Post A or Post B when one clearly conveys more restlessness. Choose Very close / neither when the difference is too small to judge or neither post expresses the criterion.
      </p>
    </div>
    """
  end
end
