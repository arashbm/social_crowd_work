defmodule SocialCrowdWork.TwoPageInstructionSet do
  @behaviour SocialCrowdWork.Instructions.InstructionSet

  @impl true
  def key, do: "two-page-instructions.v1"

  @impl true
  def pages do
    [SocialCrowdWork.TestInstructionPage, SocialCrowdWork.SecondTestInstructionPage]
  end
end
