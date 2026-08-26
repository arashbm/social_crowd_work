defmodule SocialCrowdWork.InstructionsTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWork.Instructions

  test "fetches configured instruction sets and preserves page order" do
    assert Instructions.instruction_set_keys() == [
             "psychosocial-comparison-instructions.v1",
             "test-instructions.v1"
           ]

    assert {:ok, SocialCrowdWork.Instructions.PsychosocialComparisonV1} =
             Instructions.fetch("psychosocial-comparison-instructions.v1")

    assert SocialCrowdWork.Instructions.PsychosocialComparisonV1.pages() ==
             [SocialCrowdWork.Instructions.GeneralAnnotationPageV1] ++
               SocialCrowdWork.Questionnaires.PsychosocialComparisonsV1.questions()

    assert %Phoenix.LiveView.Rendered{} =
             SocialCrowdWork.Instructions.GeneralAnnotationPageV1.render(%{})

    assert {:ok, SocialCrowdWork.TestInstructionSet} = Instructions.fetch("test-instructions.v1")

    assert SocialCrowdWork.TestInstructionSet.pages() == [
             SocialCrowdWork.TestInstructionPage
           ]

    assert :error = Instructions.fetch("unknown.v1")
  end

  test "rejects duplicate instruction set and page keys" do
    assert_raise ArgumentError, ~r/duplicate instruction set keys/, fn ->
      Instructions.validate!([
        SocialCrowdWork.TestInstructionSet,
        SocialCrowdWork.TestInstructionSet
      ])
    end

    assert_raise ArgumentError, ~r/duplicate instruction page/, fn ->
      Instructions.validate!([SocialCrowdWork.DuplicatePageInstructionSet])
    end
  end

  test "rejects instruction sets without pages" do
    assert_raise ArgumentError, ~r/must contain at least one page/, fn ->
      Instructions.validate!([SocialCrowdWork.EmptyInstructionSet])
    end
  end
end
