defmodule SocialCrowdWork.DuplicatePageInstructionSet do
  @behaviour SocialCrowdWork.Instructions.InstructionSet

  @impl true
  def key, do: "duplicate-page-instructions.v1"

  @impl true
  def pages, do: [SocialCrowdWork.TestInstructionPage, SocialCrowdWork.TestInstructionPage]
end
