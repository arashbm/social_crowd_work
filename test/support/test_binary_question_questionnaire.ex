defmodule SocialCrowdWork.TestBinaryQuestionQuestionnaire do
  @behaviour SocialCrowdWork.Questionnaires.Questionnaire

  @impl true
  def key, do: "test-binary-question.v1"

  @impl true
  def task_type, do: :binary_question

  @impl true
  def questions, do: [SocialCrowdWork.TestBinaryQuestionPrompt]
end
