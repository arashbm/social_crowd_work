defmodule SocialCrowdWork.PromptsTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWork.Prompts
  alias SocialCrowdWork.Questionnaires

  @production_prompts [
    {"low-mood.v1", SocialCrowdWork.Prompts.LowMoodV1},
    {"hopelessness.v1", SocialCrowdWork.Prompts.HopelessnessV1},
    {"worry.v1", SocialCrowdWork.Prompts.WorryV1},
    {"restlessness.v1", SocialCrowdWork.Prompts.RestlessnessV1},
    {"irritability.v1", SocialCrowdWork.Prompts.IrritabilityV1},
    {"cognitive-disruption.v1", SocialCrowdWork.Prompts.CognitiveDisruptionV1},
    {"cognitive-distortions.v1", SocialCrowdWork.Prompts.CognitiveDistortionsV1},
    {"inability-to-control-worry.v1", SocialCrowdWork.Prompts.InabilityToControlWorryV1},
    {"stress-overload.v1", SocialCrowdWork.Prompts.StressOverloadV1},
    {"social-disconnection.v1", SocialCrowdWork.Prompts.SocialDisconnectionV1},
    {"guilt-worthlessness.v1", SocialCrowdWork.Prompts.GuiltWorthlessnessV1},
    {"fatigue.v1", SocialCrowdWork.Prompts.FatigueV1},
    {"sleep-disturbance.v1", SocialCrowdWork.Prompts.SleepDisturbanceV1},
    {"suicidal-ideation.v1", SocialCrowdWork.Prompts.SuicidalIdeationV1},
    {"loss-of-interest.v1", SocialCrowdWork.Prompts.LossOfInterestV1},
    {"appetite-changes.v1", SocialCrowdWork.Prompts.AppetiteChangesV1}
  ]

  test "fetches production comparison prompts by their immutable keys" do
    Enum.each(@production_prompts, fn {key, module} ->
      assert {:ok, ^module} = Prompts.fetch(key)
      assert module.task_type() == :comparison
      assert module.choices() == [:post_a, :post_b, :equal, :skip]
      assert is_binary(module.description())
      assert %Phoenix.LiveView.Rendered{} = module.render(%{})
      assert %Phoenix.LiveView.Rendered{} = module.render(%{instruction_page: true})
      assert %Phoenix.LiveView.Rendered{} = module.detailed_instructions(%{})
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
    assert prompt.description() == "Compare both test posts against the test criterion."
    assert %Phoenix.LiveView.Rendered{} = prompt.render(%{})
  end

  test "fetches the production questionnaire and its ordered questions" do
    assert {:ok, SocialCrowdWork.Questionnaires.PsychosocialComparisonsV1} =
             Questionnaires.fetch("psychosocial-comparisons.v1")

    questionnaire = Questionnaires.fetch!("psychosocial-comparisons.v1")

    assert questionnaire.task_type() == :comparison

    assert Enum.map(questionnaire.questions(), & &1.key()) ==
             Enum.map(@production_prompts, &elem(&1, 0))
  end

  test "fetches configured questionnaire modules" do
    assert {:ok, SocialCrowdWork.TestComparisonQuestionnaire} =
             Questionnaires.fetch("test-comparison.v1")

    assert {:ok, SocialCrowdWork.TestBinaryQuestionQuestionnaire} =
             Questionnaires.fetch("test-binary-question.v1")

    assert :error = Questionnaires.fetch("unknown.v1")
  end
end
