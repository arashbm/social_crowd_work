defmodule SocialCrowdWork.Imports.ImportError do
  @moduledoc """
  A validation error tied to a location in an import manifest.
  """

  @enforce_keys [:path, :message]
  defstruct [:path, :message]

  @type t :: %__MODULE__{path: String.t(), message: String.t()}
end
