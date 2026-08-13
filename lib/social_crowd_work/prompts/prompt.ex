defmodule SocialCrowdWork.Prompts.Prompt do
  @moduledoc """
  Contract for immutable, code-defined participant prompts.

  Prompt keys include their version. Participant-facing changes therefore require
  a new module and key rather than modifying a prompt already used by a task.
  """

  @type task_type :: :comparison | :binary_question
  @type choice :: :post_a | :post_b | :equal | :yes | :no | :skip

  @callback key() :: String.t()
  @callback title() :: String.t()
  @callback task_type() :: task_type()
  @callback choices() :: [choice()]
  @callback render(map()) :: Phoenix.LiveView.Rendered.t()
end
