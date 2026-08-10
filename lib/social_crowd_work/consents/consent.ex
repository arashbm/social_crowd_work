defmodule SocialCrowdWork.Consents.Consent do
  @moduledoc """
  Contract for immutable, code-defined consent documents.

  Consent keys include their version. Changing participant-facing consent text
  requires a new module and key so each participation records the exact version
  it accepted.
  """

  @callback key() :: String.t()
  @callback render(map()) :: Phoenix.LiveView.Rendered.t()
end
