# Participant Flow

Prolific opens a condition-specific entry URL with `PROLIFIC_PID`, `STUDY_ID`, and `SESSION_ID` query parameters. The entry controller validates them, renews an encrypted cookie session, and redirects immediately to `/participate` so identifiers do not remain in application URLs.

No database record or run assignment is created before consent. Accepting the condition's versioned consent definition records consent and assigns one random available run in a single transaction. Declining clears the temporary session and saves nothing.

Tasks appear in imported order. Comparison posts preserve their imported A/B roles. Responses may be changed by navigating back before completion; the final submitted choice is retained. Completed participations and their responses are immutable.

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

After the final response, the participation is completed and redirected to Prolific. A completed-session revisit displays the completion link as a fallback.

The participant interface supports system, light, and dark themes. System is the default until a participant explicitly chooses light or dark; that preference is retained in local storage and can be returned to system mode from the visible theme switch.

Production use still requires real prompt and consent modules to be added to `SocialCrowdWork.Prompts` and `SocialCrowdWork.Consents`.
