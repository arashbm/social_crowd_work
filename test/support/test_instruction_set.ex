defmodule SocialCrowdWork.TestInstructionSet do
  @behaviour SocialCrowdWork.Instructions.InstructionSet

  @impl true
  def key, do: "test-instructions.v1"

  @impl true
  def pages, do: [SocialCrowdWork.TestInstructionPage]
end
