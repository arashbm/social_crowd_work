defmodule SocialCrowdWork.Questionnaires.PsychosocialComparisonsV1 do
  @behaviour SocialCrowdWork.Questionnaires.Questionnaire

  alias SocialCrowdWork.Prompts.{CognitiveDisruptionV1, RestlessnessV1, WorryV1}

  @impl true
  def key, do: "psychosocial-comparisons.v1"

  @impl true
  def task_type, do: :comparison

  @impl true
  def questions, do: [WorryV1, RestlessnessV1, CognitiveDisruptionV1]
end
