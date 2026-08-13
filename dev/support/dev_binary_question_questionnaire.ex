defmodule SocialCrowdWork.DevBinaryQuestionQuestionnaire do
  @behaviour SocialCrowdWork.Questionnaires.Questionnaire

  @impl true
  def key, do: "dev-binary-question.v1"

  @impl true
  def task_type, do: :binary_question

  @impl true
  def questions, do: [SocialCrowdWork.DevBinaryQuestionPrompt]
end
