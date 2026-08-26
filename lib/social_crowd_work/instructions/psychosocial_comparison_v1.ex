defmodule SocialCrowdWork.Instructions.PsychosocialComparisonV1 do
  @behaviour SocialCrowdWork.Instructions.InstructionSet

  @impl true
  def key, do: "psychosocial-comparison-instructions.v1"

  @impl true
  def pages do
    [
      SocialCrowdWork.Instructions.GeneralAnnotationPageV1,
      SocialCrowdWork.Prompts.LowMoodV1,
      SocialCrowdWork.Prompts.HopelessnessV1,
      SocialCrowdWork.Prompts.WorryV1,
      SocialCrowdWork.Prompts.RestlessnessV1,
      SocialCrowdWork.Prompts.IrritabilityV1,
      SocialCrowdWork.Prompts.CognitiveDisruptionV1,
      SocialCrowdWork.Prompts.CognitiveDistortionsV1,
      SocialCrowdWork.Prompts.InabilityToControlWorryV1,
      SocialCrowdWork.Prompts.StressOverloadV1,
      SocialCrowdWork.Prompts.SocialDisconnectionV1,
      SocialCrowdWork.Prompts.GuiltWorthlessnessV1,
      SocialCrowdWork.Prompts.FatigueV1,
      SocialCrowdWork.Prompts.SleepDisturbanceV1,
      SocialCrowdWork.Prompts.SuicidalIdeationV1,
      SocialCrowdWork.Prompts.LossOfInterestV1,
      SocialCrowdWork.Prompts.AppetiteChangesV1
    ]
  end
end
