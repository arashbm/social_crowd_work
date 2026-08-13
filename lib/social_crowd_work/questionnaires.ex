defmodule SocialCrowdWork.Questionnaires do
  @moduledoc """
  Registry for immutable questionnaire modules known to the application.

  Additional modules may be configured under
  `:social_crowd_work, :questionnaire_modules`.
  """

  alias SocialCrowdWork.DataCollection.Response

  @questionnaire_modules [SocialCrowdWork.Questionnaires.PsychosocialComparisonsV1]

  def fetch(key) when is_binary(key) do
    case Enum.find(questionnaire_modules(), &(&1.key() == key)) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  def fetch(_key), do: :error

  def fetch!(key) do
    case fetch(key) do
      {:ok, module} -> module
      :error -> raise KeyError, key: key, term: questionnaire_keys()
    end
  end

  def all, do: questionnaire_modules()
  def questionnaire_keys, do: Enum.map(questionnaire_modules(), & &1.key())

  defp questionnaire_modules do
    modules =
      @questionnaire_modules ++
        Application.get_env(:social_crowd_work, :questionnaire_modules, [])

    ensure_unique_keys!(modules)
    Enum.each(modules, &validate!/1)
    modules
  end

  defp ensure_unique_keys!(modules) do
    duplicate_keys =
      modules
      |> Enum.group_by(& &1.key())
      |> Enum.filter(fn {_key, definitions} -> length(definitions) > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicate_keys != [] do
      raise ArgumentError, "duplicate questionnaire keys: #{Enum.join(duplicate_keys, ", ")}"
    end
  end

  defp validate!(module) do
    questions = module.questions()

    if not is_list(questions) or questions == [] do
      raise ArgumentError, "questionnaire #{module.key()} must contain at least one question"
    end

    question_keys = Enum.map(questions, & &1.key())

    if Enum.any?(question_keys, &(not is_binary(&1) or String.trim(&1) == "")) do
      raise ArgumentError, "questionnaire #{module.key()} contains a blank question key"
    end

    if length(question_keys) != MapSet.size(MapSet.new(question_keys)) do
      raise ArgumentError, "questionnaire #{module.key()} contains duplicate question keys"
    end

    expected_choices = MapSet.new(Response.choices_for(module.task_type()))

    Enum.each(questions, fn question ->
      if question.task_type() != module.task_type() do
        raise ArgumentError,
              "question #{question.key()} is not compatible with questionnaire #{module.key()} task type"
      end

      choices = question.choices()

      if not is_list(choices) or expected_choices == MapSet.new() or
           length(choices) != MapSet.size(expected_choices) or
           MapSet.new(choices) != expected_choices do
        raise ArgumentError,
              "question #{question.key()} has choices incompatible with questionnaire #{module.key()}"
      end
    end)
  end
end
