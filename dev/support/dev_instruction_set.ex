defmodule SocialCrowdWork.DevInstructionSet do
  @behaviour SocialCrowdWork.Instructions.InstructionSet

  @impl true
  def key, do: "dev-instructions.v1"

  @impl true
  def pages, do: [SocialCrowdWork.DevInstructionPage]
end
