defmodule SocialCrowdWork.Prompts.CognitiveDisruptionV1 do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Prompts.Prompt

  @impl true
  def key, do: "cognitive-disruption.v1"

  @impl true
  def description,
    do:
      "Compare how strongly distress appears to interfere with clear, focused thinking in each post."

  @impl true
  def task_type, do: :comparison

  @impl true
  def choices, do: [:post_a, :post_b, :equal, :skip]

  @impl true
  def render(assigns) do
    assigns = Map.put_new(assigns, :id, "cognitive-disruption-prompt-v1")

    ~H"""
    <span
      id={@id}
      class="block text-lg font-bold leading-snug tracking-tight text-slate-950 dark:text-white sm:text-xl"
    >
      Which post shows more <u class="decoration-indigo-500 decoration-2 underline-offset-4 dark:decoration-indigo-400">difficulty thinking clearly because of distress</u>?
    </span>
    """
  end

  @impl true
  def detailed_instructions(assigns) do
    ~H"""
    <div class="space-y-4 text-sm leading-6 text-slate-600 dark:text-slate-300">
      <p>
        Read both posts in full and compare how much emotional distress disrupts thinking in each one.
      </p>
      <p>
        Look for difficulty concentrating, organizing thoughts, making sense of a situation, or thinking clearly because the writer is distressed. Do not treat ordinary uncertainty by itself as cognitive disruption.
      </p>
      <p>
        Choose Post A or Post B when one clearly shows more disruption. Choose Very close / neither when the difference is too small to judge or neither post expresses the criterion.
      </p>
    </div>
    """
  end
end
