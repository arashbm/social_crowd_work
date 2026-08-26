defmodule SocialCrowdWork.Instructions.GeneralAnnotationPageV1 do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Instructions.Page

  @impl true
  def key, do: "general-annotation-instructions.v1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="general-annotation-instructions-v1" class="space-y-8">
      <header>
        <p class="text-xs font-bold uppercase tracking-[0.16em] text-indigo-600 dark:text-indigo-300">
          Before you begin
        </p>
        <h1 class="mt-2 text-2xl font-bold tracking-tight text-slate-950 dark:text-white sm:text-3xl">
          General Annotation Instructions
        </h1>
        <p class="mt-4 text-base leading-7 text-slate-600 dark:text-slate-300">
          In this task, you will compare two social media posts for the presence and strength of social and psychological factors.
        </p>
      </header>

      <section aria-labelledby="comparison-guidance-title">
        <h2 id="comparison-guidance-title" class="text-lg font-bold text-slate-950 dark:text-white">
          When comparing two posts
        </h2>
        <ul class="mt-3 space-y-3 text-sm leading-6 text-slate-600 dark:text-slate-300 sm:text-base">
          <li class="flex gap-3">
            <span class="mt-2 size-1.5 shrink-0 rounded-full bg-indigo-500" />
            <span>Choose the post that shows
            <strong class="font-bold text-slate-900 dark:text-white">more evidence</strong>
            of the factor, such as worry or irritability.</span>
          </li>
          <li class="flex gap-3">
            <span class="mt-2 size-1.5 shrink-0 rounded-full bg-indigo-500" />
            <span>A post does not need to contain exact words such as "worried" or "anxious." Consider its meaning and overall expression.</span>
          </li>
        </ul>
      </section>

      <section aria-labelledby="look-for-title">
        <h2 id="look-for-title" class="text-lg font-bold text-slate-950 dark:text-white">
          What should you look for?
        </h2>
        <p class="mt-2 text-sm leading-6 text-slate-600 dark:text-slate-300 sm:text-base">
          Look only at what the person expresses in the post.
        </p>

        <div class="mt-4 grid overflow-hidden rounded-2xl border border-slate-200 bg-white dark:border-slate-700 dark:bg-slate-950/50 md:grid-cols-2">
          <div class="border-b border-slate-200 p-5 dark:border-slate-700 md:border-b-0 md:border-r">
            <h3 class="flex items-center gap-2 font-bold text-emerald-700 dark:text-emerald-300">
              <span class="grid size-6 place-items-center rounded-full bg-emerald-100 text-sm dark:bg-emerald-500/15">✓</span>
              Do
            </h3>
            <ul class="mt-4 space-y-3 text-sm leading-6 text-slate-600 dark:text-slate-300">
              <li class="flex gap-2">
                <span class="font-bold text-emerald-600 dark:text-emerald-400">✓</span>
                Observe feelings, thoughts, and concerns expressed by the writer.
              </li>
              <li class="flex gap-2">
                <span class="font-bold text-emerald-600 dark:text-emerald-400">✓</span>
                Consider both direct and indirect expressions.
              </li>
              <li class="flex gap-2">
                <span class="font-bold text-emerald-600 dark:text-emerald-400">✓</span>
                Read the whole post to understand its meaning before making a choice.
              </li>
            </ul>
          </div>
          <div class="p-5">
            <h3 class="flex items-center gap-2 font-bold text-rose-700 dark:text-rose-300">
              <span class="grid size-6 place-items-center rounded-full bg-rose-100 text-sm dark:bg-rose-500/15">✗</span>
              Do not
            </h3>
            <ul class="mt-4 space-y-3 text-sm leading-6 text-slate-600 dark:text-slate-300">
              <li class="flex gap-2">
                <span class="font-bold text-rose-600 dark:text-rose-400">✗</span>
                Presume feelings that are not expressed.
              </li>
              <li class="flex gap-2">
                <span class="font-bold text-rose-600 dark:text-rose-400">✗</span>
                Label a post only because it discusses a negative or sensitive topic.
              </li>
            </ul>
          </div>
        </div>
      </section>

      <section
        aria-labelledby="example-title"
        class="border-t border-slate-200 pt-8 dark:border-slate-700"
      >
        <p class="text-xs font-bold uppercase tracking-[0.14em] text-indigo-600 dark:text-indigo-300">
          Demonstration
        </p>
        <h2
          id="example-title"
          class="mt-2 text-xl font-bold tracking-tight text-slate-950 dark:text-white"
        >
          Example: comparing worry
        </h2>

        <div class="mt-5 grid gap-3 md:grid-cols-2">
          <.example_post label="Post A">
            Can't stop shaking before this job interview. What if my mind goes completely blank on the technical questions? What if they realize right away that I'm totally underqualified and I blow my only shot?
          </.example_post>
          <.example_post label="Post B">
            Didn't get the job. Honestly, nothing ever goes right for me anyway, so I don't know why I even bothered submitting the application.
          </.example_post>
        </div>

        <div aria-label="Example answer choices" class="mt-4 grid gap-2 sm:grid-cols-3">
          <.example_choice shortcut="A" selected>Post A</.example_choice>
          <.example_choice shortcut="S">Very close / neither</.example_choice>
          <.example_choice shortcut="D">Post B</.example_choice>
        </div>

        <div class="mt-6 rounded-2xl border border-indigo-200 bg-indigo-50 p-5 dark:border-indigo-500/30 dark:bg-indigo-500/10">
          <p class="font-semibold text-slate-950 dark:text-white">
            Selection:
            <span class="text-indigo-700 dark:text-indigo-300">Post A shows more worry.</span>
          </p>
          <p class="mt-3 text-sm leading-6 text-slate-600 dark:text-slate-300">
            <strong class="font-bold text-slate-900 dark:text-white">Why:</strong>
            Worry is about dreading the future: getting stuck in "what-if" thoughts, picturing a worst-case scenario, and having physical reactions such as shaking. Post B shows sadness, hopelessness, and giving up over something that already happened, but it does not have the same tense, nervous energy about what might happen next.
          </p>
        </div>
      </section>
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp example_post(assigns) do
    ~H"""
    <article class="overflow-hidden rounded-xl border border-slate-200 bg-slate-50 dark:border-slate-700 dark:bg-slate-950/70">
      <p class="border-b border-slate-200 px-4 py-2 text-xs font-bold uppercase tracking-[0.14em] text-indigo-600 dark:border-slate-700 dark:text-indigo-300">
        {@label}
      </p>
      <p class="p-4 text-sm leading-6 text-slate-700 dark:text-slate-200">
        {render_slot(@inner_block)}
      </p>
    </article>
    """
  end

  attr :shortcut, :string, required: true
  attr :selected, :boolean, default: false
  slot :inner_block, required: true

  defp example_choice(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-2 rounded-xl border px-4 py-3 text-left text-sm font-semibold",
      if(@selected,
        do: "border-indigo-600 bg-indigo-700 text-white dark:border-indigo-400 dark:bg-indigo-500/30",
        else:
          "border-slate-300 bg-white text-slate-700 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
      )
    ]}>
      <kbd class="inline-flex min-w-5 items-center justify-center rounded border border-current px-1 font-mono text-[10px] font-bold leading-4">
        {@shortcut}
      </kbd>
      <span>{render_slot(@inner_block)}</span>
    </div>
    """
  end
end
