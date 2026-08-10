defmodule SocialCrowdWork.DevConsent do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Consents.Consent

  @impl true
  def key, do: "dev-consent.v1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dev-consent-content" class="space-y-5">
      <div>
        <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700">
          Local development only
        </p>
        <h1 class="mt-2 text-3xl font-semibold tracking-tight text-slate-950 dark:text-white">
          Development study consent
        </h1>
      </div>
      <div class="space-y-4 leading-7 text-slate-700 dark:text-slate-300">
        <p>
          This is placeholder consent content for exercising the application locally. It is not approved research consent language.
        </p>
        <p>
          Continuing creates a fake development participation and stores your task selections in the local database.
        </p>
      </div>
    </div>
    """
  end
end
