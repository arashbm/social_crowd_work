# Consent Definitions

Consent documents are immutable, code-defined modules implementing `SocialCrowdWork.Consents.Consent`. Their external keys include a version, such as `main-consent.v1`. Participant-facing changes require a new module and key.

Each condition references the consent key participants must accept. A condition cannot be activated until it has a known consent key, Prolific study ID, and completion code. Acceptance and run allocation occur in one transaction; declining consent creates no participation or run assignment.

There are currently no production consent definitions. `SocialCrowdWork.TestConsent` is compiled only for tests and cannot be selected in a deployed environment.
