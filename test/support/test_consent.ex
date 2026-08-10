defmodule SocialCrowdWork.TestConsent do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Consents.Consent

  @impl true
  def key, do: "test-consent.v1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="test-consent-content" class="space-y-5">
      <div>
        <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700">
          Before you begin
        </p>
        <h1 class="mt-2 text-3xl font-semibold tracking-tight text-slate-950 dark:text-white">
          Test consent
        </h1>
      </div>
      <p class="leading-7 text-slate-700 dark:text-slate-300">
        This placeholder is available only in automated tests.
      </p>
    </div>
    """
  end
end
