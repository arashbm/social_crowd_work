defmodule SocialCrowdWork.PromptsTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWork.Prompts

  test "fetches configured prompt modules by their external string keys" do
    assert {:ok, SocialCrowdWork.TestComparisonPrompt} =
             Prompts.fetch("test-comparison.v1")

    assert {:ok, SocialCrowdWork.TestBinaryQuestionPrompt} =
             Prompts.fetch("test-binary-question.v1")

    assert :error = Prompts.fetch("unknown.v1")
    assert :error = Prompts.fetch(:untrusted_atom)
  end

  test "exposes task type, rendered content, and allowed choices from a definition" do
    prompt = Prompts.fetch!("test-comparison.v1")

    assert prompt.task_type() == :comparison
    assert prompt.choices() == [:post_a, :post_b, :equal, :skip]
    assert %Phoenix.LiveView.Rendered{} = prompt.render(%{})
  end
end
