defmodule SocialCrowdWork.Questionnaires.Questionnaire do
  @moduledoc """
  Contract for immutable, code-defined questionnaires.

  Questionnaire keys include their version. A questionnaire groups an ordered,
  nonempty set of prompt modules that share one task type and choice set.
  """

  alias SocialCrowdWork.Prompts.Prompt

  @callback key() :: String.t()
  @callback task_type() :: Prompt.task_type()
  @callback questions() :: [module()]
end
