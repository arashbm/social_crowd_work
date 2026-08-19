defmodule SocialCrowdWork.EmptyInstructionSet do
  @behaviour SocialCrowdWork.Instructions.InstructionSet

  @impl true
  def key, do: "empty-instructions.v1"

  @impl true
  def pages, do: []
end
