defmodule SocialCrowdWork.TestInstructionPage do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Instructions.Page

  @impl true
  def key, do: "test-instructions-introduction.v1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="test-instruction-page">Test instructions</div>
    """
  end
end
