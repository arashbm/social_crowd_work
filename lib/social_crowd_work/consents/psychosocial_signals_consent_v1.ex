defmodule SocialCrowdWork.Consents.PsychosocialSignalsConsentV1 do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Consents.Consent

  @impl true
  def key, do: "psychosocial-signals-consent.v1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="psychosocial-signals-consent-v1" class="space-y-8">
      <header>
        <p class="text-sm font-semibold uppercase tracking-[0.16em] text-indigo-700 dark:text-indigo-300">
          Before you begin
        </p>
        <h1 class="mt-2 text-3xl font-semibold tracking-tight text-slate-950 dark:text-white">
          Research participation consent
        </h1>
        <p class="mt-3 leading-7 text-slate-600 dark:text-slate-300">
          Review the privacy notice in full, then read each statement before deciding whether to participate.
        </p>
      </header>

      <section aria-labelledby="privacy-notice-heading" class="space-y-3">
        <div class="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.14em] text-slate-500 dark:text-slate-400">
              Study document
            </p>
            <h2
              id="privacy-notice-heading"
              class="mt-1 text-xl font-semibold text-slate-950 dark:text-white"
            >
              Research study privacy notice
            </h2>
          </div>
          <a
            id="open-privacy-notice"
            href="/documents/research_study_privacy_notice.pdf"
            target="_blank"
            rel="noopener noreferrer"
            class="text-sm font-semibold text-indigo-700 underline decoration-indigo-300 underline-offset-4 transition hover:text-indigo-500 dark:text-indigo-300 dark:decoration-indigo-700 dark:hover:text-indigo-200"
          >
            Open PDF in a new tab
          </a>
        </div>

        <div class="overflow-hidden rounded-2xl border border-slate-300 bg-slate-100 shadow-inner dark:border-slate-700 dark:bg-slate-950">
          <iframe
            id="privacy-notice-document"
            src="/documents/research_study_privacy_notice.pdf"
            title="Research study privacy notice"
            class="h-[70vh] min-h-[32rem] max-h-[46rem] w-full bg-white"
          ></iframe>
        </div>
      </section>

      <section
        aria-labelledby="consent-statements-heading"
        class="rounded-2xl border border-slate-200 bg-slate-50 p-6 dark:border-slate-700 dark:bg-slate-950/60 sm:p-7"
      >
        <h2
          id="consent-statements-heading"
          class="text-xl font-semibold text-slate-950 dark:text-white"
        >
          Consent statements
        </h2>
        <div class="mt-5 space-y-5 leading-7 text-slate-700 dark:text-slate-300">
          <p>
            I understand that participation in the research is voluntary and that I may at any time, without giving a reason, withdraw or discontinue my participation. This will not result in any negative consequences for me. Research materials collected from me up until the point of withdrawal or discontinuation may still be used in the research, but I have the rights related to the processing of personal data as stated in the privacy notice.
          </p>
          <p>
            I understand that my monetary compensation is distributed via the Prolific platform. I am fully responsible for declaring this income to my local tax authority according to my home country's laws.
          </p>
          <p>
            By consenting, I acknowledge that this study is strictly non-medical and involves no physical or psychological interventions aimed at altering health outcomes.
          </p>
          <p>
            I confirm that I have received the information sheet for participants and the privacy notice, and I have had the opportunity to ask the researchers clarifying questions. I have thus received sufficient information about the content of the research, its process, and what participation means for me. I have also understood how and on what legal basis my personal data will be processed and what my rights are regarding the processing of personal data.
          </p>
          <p class="font-semibold text-slate-950 dark:text-white">
            I give my consent to participate in the research.
          </p>
        </div>
      </section>
    </div>
    """
  end
end
