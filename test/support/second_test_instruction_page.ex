defmodule SocialCrowdWork.SecondTestInstructionPage do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Instructions.Page

  @impl true
  def key, do: "test-instructions-task-example.v1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="second-test-instruction-page">Task example</div>
    """
  end
end
