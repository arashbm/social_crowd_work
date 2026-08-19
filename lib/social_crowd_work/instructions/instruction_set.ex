defmodule SocialCrowdWork.Instructions.InstructionSet do
  @moduledoc """
  Contract for an immutable, code-defined ordered set of instruction pages.
  """

  @callback key() :: String.t()
  @callback pages() :: [module()]
end
