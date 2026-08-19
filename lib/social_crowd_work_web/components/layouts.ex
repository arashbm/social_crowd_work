defmodule SocialCrowdWorkWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SocialCrowdWorkWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :variant, :atom, default: :app, values: [:app, :participant, :admin]

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%= cond do %>
      <% @variant == :participant -> %>
        <div class="relative min-h-screen overflow-hidden bg-[#f5f3ee] text-slate-900 transition-colors dark:bg-[#0d1117] dark:text-slate-100">
          <div class="pointer-events-none absolute inset-x-0 top-0 h-72 bg-[radial-gradient(circle_at_top_left,rgba(79,70,229,0.13),transparent_58%)] dark:bg-[radial-gradient(circle_at_top_left,rgba(99,102,241,0.17),transparent_58%)]" />
          <div class="pointer-events-none absolute -right-24 top-48 size-72 rounded-full border border-indigo-200/60 dark:border-indigo-900/50" />
          <div class="relative mx-auto flex min-h-screen w-full max-w-6xl flex-col px-2 py-2 sm:px-8 sm:py-6">
            <div id="participant-toolbar" class="flex shrink-0 justify-end">
              <.participant_theme_toggle />
            </div>
            <main class="flex flex-1 items-start py-1 sm:items-center sm:py-6">
              <div class="w-full">{render_slot(@inner_block)}</div>
            </main>
          </div>
        </div>
      <% @variant == :admin -> %>
        <div class="min-h-screen bg-slate-100 text-slate-950 dark:bg-slate-950 dark:text-slate-100">
          <header class="sticky top-0 z-30 border-b border-slate-200 bg-white/95 backdrop-blur dark:border-slate-800 dark:bg-slate-900/95">
            <div class="mx-auto flex h-16 max-w-[1600px] items-center justify-between gap-4 px-4 sm:px-6">
              <.link
                navigate={~p"/admin"}
                class="flex items-center gap-3 font-semibold tracking-tight"
              >
                <span class="grid size-9 place-items-center rounded-xl bg-indigo-600 text-sm font-black text-white">SC</span>
                <span class="hidden sm:inline">Research operations</span>
              </.link>
              <div class="flex items-center gap-3">
                <.participant_theme_toggle />
                <span class="hidden max-w-52 truncate text-sm text-slate-500 dark:text-slate-400 md:block">
                  {@current_scope.admin.email}
                </span>
                <.link
                  href={~p"/admins/log-out"}
                  method="delete"
                  class="rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 transition hover:bg-slate-100 hover:text-slate-950 dark:text-slate-300 dark:hover:bg-slate-800 dark:hover:text-white"
                >
                  Log out
                </.link>
              </div>
            </div>
          </header>
          <div class="mx-auto grid max-w-[1600px] lg:grid-cols-[15rem_minmax(0,1fr)]">
            <nav class="border-b border-slate-200 bg-white px-3 py-3 dark:border-slate-800 dark:bg-slate-900 lg:min-h-[calc(100vh-4rem)] lg:border-b-0 lg:border-r lg:px-4 lg:py-6">
              <div class="flex gap-1 overflow-x-auto lg:flex-col">
                <.admin_nav_link href={~p"/admin"} icon="hero-squares-2x2">Overview</.admin_nav_link>
                <.admin_nav_link href={~p"/admin/imports"} icon="hero-arrow-up-tray">Imports</.admin_nav_link>
                <.admin_nav_link href={~p"/admin/conditions"} icon="hero-adjustments-horizontal">Conditions</.admin_nav_link>
                <.admin_nav_link href={~p"/admin/participations"} icon="hero-user-group">Participations</.admin_nav_link>
                <.admin_nav_link href={~p"/admin/exports"} icon="hero-arrow-down-tray">Exports</.admin_nav_link>
                <.admin_nav_link href={~p"/admin/definitions"} icon="hero-book-open">Definitions</.admin_nav_link>
                <.admin_nav_link href={~p"/admin/audit"} icon="hero-shield-check">Audit</.admin_nav_link>
              </div>
            </nav>
            <main class="min-w-0 px-4 py-6 sm:px-6 lg:px-10 lg:py-9">
              {render_slot(@inner_block)}
            </main>
          </div>
        </div>
      <% true -> %>
        <header class="navbar px-4 sm:px-6 lg:px-8">
          <div class="flex-1">
            <a href="/" class="flex-1 flex w-fit items-center gap-2">
              <img src={~p"/images/logo.svg"} width="36" />
              <span class="text-sm font-semibold">v{Application.spec(:phoenix, :vsn)}</span>
            </a>
          </div>
          <div class="flex-none">
            <ul class="flex flex-column px-1 space-x-4 items-center">
              <li>
                <a href="https://phoenixframework.org/" class="btn btn-ghost">Website</a>
              </li>
              <li>
                <a href="https://github.com/phoenixframework/phoenix" class="btn btn-ghost">GitHub</a>
              </li>
              <li>
                <.theme_toggle />
              </li>
              <li>
                <a href="https://phoenix.hexdocs.pm/overview.html" class="btn btn-primary">
                  Get Started <span aria-hidden="true">&rarr;</span>
                </a>
              </li>
            </ul>
          </div>
        </header>

        <main class="px-4 py-20 sm:px-6 lg:px-8">
          <div class="mx-auto max-w-2xl space-y-4">
            {render_slot(@inner_block)}
          </div>
        </main>
    <% end %>

    <.flash_group flash={@flash} />
    """
  end

  attr :href, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp admin_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="inline-flex shrink-0 items-center gap-2 rounded-xl px-3 py-2.5 text-sm font-semibold text-slate-600 transition hover:bg-indigo-50 hover:text-indigo-800 dark:text-slate-300 dark:hover:bg-indigo-500/10 dark:hover:text-indigo-300"
    >
      <.icon name={@icon} class="size-5" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  def participant_theme_toggle(assigns) do
    ~H"""
    <div
      id="participant-theme-switch"
      role="radiogroup"
      aria-label="Color theme"
      class="relative grid grid-cols-3 overflow-hidden rounded-xl border border-slate-300 bg-white/80 p-1 text-slate-600 shadow-sm backdrop-blur transition-colors dark:border-slate-700 dark:bg-slate-900/80 dark:text-slate-300"
    >
      <div class="pointer-events-none absolute bottom-1 left-1 top-1 w-[calc((100%_-_0.5rem)/3)] rounded-lg bg-indigo-100 shadow-sm transition-[left] [[data-theme=light]_&]:left-[33.333%] [[data-theme=dark]_&]:left-[calc(66.666%_-_0.25rem)] [[data-theme-source=system]_&]:!left-1 dark:bg-indigo-500/25" />
      <button
        id="theme-system"
        type="button"
        role="radio"
        aria-checked="true"
        aria-label="Use system theme"
        title="System theme"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
        class="relative z-10 inline-flex size-8 items-center justify-center rounded-md transition hover:text-slate-950 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:hover:text-white sm:size-9 sm:rounded-lg"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>
      <button
        id="theme-light"
        type="button"
        role="radio"
        aria-checked="false"
        aria-label="Use light theme"
        title="Light theme"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        class="relative z-10 inline-flex size-8 items-center justify-center rounded-md transition hover:text-slate-950 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:hover:text-white sm:size-9 sm:rounded-lg"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>
      <button
        id="theme-dark"
        type="button"
        role="radio"
        aria-checked="false"
        aria-label="Use dark theme"
        title="Dark theme"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        class="relative z-10 inline-flex size-8 items-center justify-center rounded-md transition hover:text-slate-950 focus:outline-none focus:ring-2 focus:ring-indigo-500 dark:hover:text-white sm:size-9 sm:rounded-lg"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
