defmodule SocialCrowdWork.DevInstructionPage do
  use Phoenix.Component

  @behaviour SocialCrowdWork.Instructions.Page

  @impl true
  def key, do: "dev-instructions-introduction.v1"

  @impl true
  def render(assigns) do
    ~H"""
    <div id="dev-instruction-page">
      <h1>Development instructions</h1>
      <p>This instruction page is available only in development.</p>
    </div>
    """
  end
end
