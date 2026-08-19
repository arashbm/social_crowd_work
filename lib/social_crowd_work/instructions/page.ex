defmodule SocialCrowdWork.Instructions.Page do
  @moduledoc """
  Contract for one immutable, code-defined instruction page.

  Page keys include their version and are unique within an instruction set.
  """

  @callback key() :: String.t()
  @callback render(map()) :: Phoenix.LiveView.Rendered.t()
end
