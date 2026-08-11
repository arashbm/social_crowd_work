defmodule SocialCrowdWork.PromptsTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWork.Prompts

  @production_prompts [
    {"worry.v1", SocialCrowdWork.Prompts.WorryV1},
    {"restlessness.v1", SocialCrowdWork.Prompts.RestlessnessV1},
    {"cognitive-disruption.v1", SocialCrowdWork.Prompts.CognitiveDisruptionV1}
  ]

  test "fetches production comparison prompts by their immutable keys" do
    Enum.each(@production_prompts, fn {key, module} ->
      assert {:ok, ^module} = Prompts.fetch(key)
      assert module.task_type() == :comparison
      assert module.choices() == [:post_a, :post_b, :equal, :skip]
      assert %Phoenix.LiveView.Rendered{} = module.render(%{})
    end)
  end

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
