defmodule SocialCrowdWork.TestComparisonQuestionnaire do
  @behaviour SocialCrowdWork.Questionnaires.Questionnaire

  @impl true
  def key, do: "test-comparison.v1"

  @impl true
  def task_type, do: :comparison

  @impl true
  def questions, do: [SocialCrowdWork.TestComparisonPrompt]
end
