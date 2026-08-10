defmodule SocialCrowdWorkWeb.AdminComponents do
  use Phoenix.Component

  import SocialCrowdWorkWeb.CoreComponents

  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :actions

  def admin_header(assigns) do
    ~H"""
    <header class="mb-7 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 class="text-3xl font-semibold tracking-tight text-slate-950 dark:text-white">{@title}</h1>
        <p
          :if={@description}
          class="mt-2 max-w-3xl text-sm leading-6 text-slate-600 dark:text-slate-400"
        >
          {@description}
        </p>
      </div>
      <div :if={@actions != []} class="flex shrink-0 items-center gap-2">{render_slot(@actions)}</div>
    </header>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :icon, :string, required: true
  attr :tone, :atom, default: :indigo, values: [:indigo, :emerald, :amber, :slate]

  def stat_card(assigns) do
    ~H"""
    <div class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm dark:border-slate-800 dark:bg-slate-900">
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="text-sm font-medium text-slate-500 dark:text-slate-400">{@label}</p>
          <p class="mt-2 text-3xl font-semibold tabular-nums tracking-tight text-slate-950 dark:text-white">
            {@value}
          </p>
        </div>
        <span class={[
          "grid size-10 place-items-center rounded-xl",
          @tone == :indigo &&
            "bg-indigo-100 text-indigo-700 dark:bg-indigo-500/15 dark:text-indigo-300",
          @tone == :emerald &&
            "bg-emerald-100 text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-300",
          @tone == :amber && "bg-amber-100 text-amber-700 dark:bg-amber-500/15 dark:text-amber-300",
          @tone == :slate && "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-300"
        ]}>
          <.icon name={@icon} class="size-5" />
        </span>
      </div>
    </div>
    """
  end

  attr :status, :atom, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex rounded-full px-2.5 py-1 text-xs font-bold capitalize",
      @status in [:active, :completed] &&
        "bg-emerald-100 text-emerald-800 dark:bg-emerald-500/15 dark:text-emerald-300",
      @status in [:paused, :assigned, :in_progress] &&
        "bg-amber-100 text-amber-800 dark:bg-amber-500/15 dark:text-amber-300",
      @status in [:draft] &&
        "bg-indigo-100 text-indigo-800 dark:bg-indigo-500/15 dark:text-indigo-300",
      @status in [:closed] && "bg-slate-200 text-slate-700 dark:bg-slate-700 dark:text-slate-200"
    ]}>
      {@status |> Atom.to_string() |> String.replace("_", " ")}
    </span>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :message, :string, required: true

  def admin_empty(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-2xl border border-dashed border-slate-300 bg-white/60 px-6 py-12 text-center dark:border-slate-700 dark:bg-slate-900/50"
    >
      <h2 class="font-semibold text-slate-900 dark:text-white">{@title}</h2>
      <p class="mt-2 text-sm text-slate-500 dark:text-slate-400">{@message}</p>
    </div>
    """
  end

  def mask_identifier(value) when is_binary(value) and byte_size(value) > 10 do
    String.slice(value, 0, 4) <> "..." <> String.slice(value, -4, 4)
  end

  def mask_identifier(value), do: value
end
