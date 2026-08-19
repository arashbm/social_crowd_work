# Participant Flow

Prolific opens a condition-specific `/enter/:entry_token` URL with `PROLIFIC_PID`, `STUDY_ID`, and `SESSION_ID` query parameters. The entry controller validates them, stores a temporary launch record, and redirects immediately to `/participate/:launch_token`. The random bearer token contains no participant data, and only its SHA-256 hash is stored in PostgreSQL.

Every valid entry creates an independent launch token, so multiple studies remain correct across tabs, refreshes, and LiveView reconnects. Pre-consent launches expire after 24 hours. Consent attaches the launch to the participation and extends it for seven days; expired records are removed lazily when another launch is created.

No participation or run assignment is created before consent. Accepting the condition's versioned consent definition records consent, assigns one random available run, and attaches the launch in a single transaction. Declining deletes the presented pre-consent launch. Completion consumes all launches attached to that participation before redirecting to Prolific.

After consent, a condition may present an immutable, versioned instruction set before any task response can be recorded. The participation snapshots the condition's instruction key, advances its code-defined pages in order, and stores the number of pages completed plus the server completion timestamp. Conditions without an instruction set continue directly to tasks.

Tasks appear in imported order. Each task renders its stimuli once and uses its versioned questionnaire to present a fixed, code-defined sequence of questions. The active question is expanded, later questions remain locked, and answered questions may be reopened and changed before completion. Answering the final question advances to the next task. Comparison posts preserve their imported A/B roles. Completed participations and their responses are immutable.

All annotation actions have visible keyboard shortcuts and submit immediately:

| Action | Shortcut |
| --- | --- |
| Choose Post A / Yes | `A` |
| Equal / No | `S` |
| Choose Post B | `D` |
| Skip | `X` |
| Previous task | `Z` |
| Accept consent | `Enter` or `Space` |
| Continue to Prolific | `Enter` or `Space` |

After the final response, the participation is completed and redirected through a context-cleanup endpoint to Prolific. A completed-session revisit displays the completion link as a fallback.

The participant interface supports system, light, and dark themes. System is the default until a participant explicitly chooses light or dark; that preference is retained in local storage and can be returned to system mode from the visible theme switch.

Raw instruction telemetry records page renders and exposure intervals from the client, including visible/focused milliseconds and close reasons such as `instruction_changed`, `visibility_hidden`, `window_blurred`, and `page_unloaded`. Page advancement and instruction completion are server-owned events appended alongside the persisted progress update. These events remain raw and are not used to calculate metrics in the application.

Production definitions live in `SocialCrowdWork.Instructions`, `SocialCrowdWork.Questionnaires`, `SocialCrowdWork.Prompts`, and `SocialCrowdWork.Consents`. Participant-facing changes require new versioned keys.
