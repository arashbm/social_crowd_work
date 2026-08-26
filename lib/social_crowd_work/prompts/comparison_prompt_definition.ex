defmodule SocialCrowdWork.Prompts.ComparisonPromptDefinition do
  @moduledoc false

  defmacro __using__(name) do
    quote do
      @behaviour SocialCrowdWork.Prompts.Prompt

      @impl true
      def key, do: SocialCrowdWork.Prompts.ComparisonPrompt.definition!(unquote(name)).key

      @impl true
      def description,
        do: SocialCrowdWork.Prompts.ComparisonPrompt.definition!(unquote(name)).description

      @impl true
      def task_type, do: :comparison

      @impl true
      def choices, do: [:post_a, :post_b, :equal, :skip]

      @impl true
      def render(assigns) do
        definition = SocialCrowdWork.Prompts.ComparisonPrompt.definition!(unquote(name))

        if Map.get(assigns, :instruction_page, false) do
          SocialCrowdWork.Prompts.ComparisonPrompt.instruction_page(definition)
        else
          SocialCrowdWork.Prompts.ComparisonPrompt.question(definition, Map.get(assigns, :id))
        end
      end

      @impl true
      def detailed_instructions(_assigns) do
        SocialCrowdWork.Prompts.ComparisonPrompt.guidance(
          SocialCrowdWork.Prompts.ComparisonPrompt.definition!(unquote(name))
        )
      end
    end
  end
end
