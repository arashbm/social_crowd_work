defmodule SocialCrowdWork.Imports.Manifest do
  @moduledoc false

  alias SocialCrowdWork.Experiments.Task
  alias SocialCrowdWork.Imports.ImportError
  alias SocialCrowdWork.Instructions
  alias SocialCrowdWork.Questionnaires

  @format_version "3"
  @top_level_keys ["format_version", "conditions"]
  @condition_keys ["key", "task_type", "variants", "instructions_key", "runs"]
  @run_keys ["key", "tasks"]
  @task_keys ["position", "questionnaire_key", "stimuli"]

  def validate(contents) when is_binary(contents) do
    case Jason.decode(contents) do
      {:ok, document} ->
        validate_document(document)

      {:error, error} ->
        {:error, [error("$", "contains invalid JSON: #{Exception.message(error)}")]}
    end
  end

  defp validate_document(document) when is_map(document) do
    errors = unknown_key_errors(document, @top_level_keys, "$")

    {format_version, errors} =
      required_string(document, "format_version", "format_version", errors)

    errors =
      if format_version && format_version != @format_version do
        [error("format_version", "must be #{@format_version}") | errors]
      else
        errors
      end

    {conditions, errors} = required_non_empty_list(document, "conditions", "conditions", errors)
    {normalized_conditions, errors} = validate_conditions(conditions, errors)
    errors = duplicate_errors(normalized_conditions, :key, "conditions", errors)

    if errors == [] do
      {:ok, %{format_version: format_version, conditions: normalized_conditions}}
    else
      {:error, Enum.reverse(errors)}
    end
  end

  defp validate_document(_document), do: {:error, [error("$", "must be a JSON object")]}

  defp validate_conditions(nil, errors), do: {[], errors}

  defp validate_conditions(conditions, errors) do
    conditions
    |> Enum.with_index()
    |> Enum.reduce({[], errors}, fn {condition, index}, {normalized, errors} ->
      path = "conditions[#{index}]"
      {value, errors} = validate_condition(condition, path, errors)
      normalized = if value, do: [value | normalized], else: normalized
      {normalized, errors}
    end)
    |> then(fn {normalized, errors} -> {Enum.reverse(normalized), errors} end)
  end

  defp validate_condition(condition, path, errors) when is_map(condition) do
    errors = unknown_key_errors(condition, @condition_keys, path) ++ errors
    {key, errors} = required_string(condition, "key", "#{path}.key", errors)
    {task_type, errors} = task_type(condition, path, errors)
    {variants, errors} = required_map(condition, "variants", "#{path}.variants", errors)
    {instructions_key, errors} = optional_string(condition, "instructions_key", path, errors)
    errors = validate_instructions_key(instructions_key, "#{path}.instructions_key", errors)
    {runs, errors} = required_non_empty_list(condition, "runs", "#{path}.runs", errors)
    {normalized_runs, errors} = validate_runs(runs, task_type, path, errors)
    errors = duplicate_errors(normalized_runs, :external_key, "#{path}.runs", errors)

    value =
      if key && task_type && variants && runs do
        %{
          key: key,
          task_type: task_type,
          variants: variants,
          instructions_key: instructions_key,
          runs: normalized_runs
        }
      end

    {value, errors}
  end

  defp validate_condition(_condition, path, errors) do
    {nil, [error(path, "must be an object") | errors]}
  end

  defp validate_runs(nil, _task_type, _condition_path, errors), do: {[], errors}

  defp validate_runs(runs, task_type, condition_path, errors) do
    runs
    |> Enum.with_index()
    |> Enum.reduce({[], errors}, fn {run, index}, {normalized, errors} ->
      path = "#{condition_path}.runs[#{index}]"
      {value, errors} = validate_run(run, task_type, path, errors)
      normalized = if value, do: [value | normalized], else: normalized
      {normalized, errors}
    end)
    |> then(fn {normalized, errors} -> {Enum.reverse(normalized), errors} end)
  end

  defp validate_run(run, task_type, path, errors) when is_map(run) do
    errors = unknown_key_errors(run, @run_keys, path) ++ errors
    {key, errors} = required_string(run, "key", "#{path}.key", errors)
    {tasks, errors} = required_non_empty_list(run, "tasks", "#{path}.tasks", errors)
    {normalized_tasks, errors} = validate_tasks(tasks, task_type, path, errors)
    errors = duplicate_errors(normalized_tasks, :position, "#{path}.tasks", errors)
    errors = contiguous_position_errors(tasks, "#{path}.tasks", errors)

    value = if key && tasks, do: %{external_key: key, tasks: normalized_tasks}
    {value, errors}
  end

  defp validate_run(_run, _task_type, path, errors) do
    {nil, [error(path, "must be an object") | errors]}
  end

  defp validate_tasks(nil, _task_type, _run_path, errors), do: {[], errors}

  defp validate_tasks(tasks, task_type, run_path, errors) do
    tasks
    |> Enum.with_index()
    |> Enum.reduce({[], errors}, fn {task, index}, {normalized, errors} ->
      path = "#{run_path}.tasks[#{index}]"
      {value, errors} = validate_task(task, task_type, path, errors)
      normalized = if value, do: [value | normalized], else: normalized
      {normalized, errors}
    end)
    |> then(fn {normalized, errors} -> {Enum.reverse(normalized), errors} end)
  end

  defp validate_task(task, task_type, path, errors) when is_map(task) do
    errors = unknown_key_errors(task, @task_keys, path) ++ errors
    {position, errors} = positive_integer(task, "position", "#{path}.position", errors)

    {questionnaire_key, errors} =
      required_string(task, "questionnaire_key", "#{path}.questionnaire_key", errors)

    {stimuli, errors} = required_map(task, "stimuli", "#{path}.stimuli", errors)

    errors =
      validate_questionnaire(
        questionnaire_key,
        task_type,
        "#{path}.questionnaire_key",
        errors
      )

    errors = validate_stimuli(stimuli, task_type, "#{path}.stimuli", errors)

    value =
      if position && questionnaire_key && stimuli do
        %{position: position, questionnaire_key: questionnaire_key, stimuli: stimuli}
      end

    {value, errors}
  end

  defp validate_task(_task, _task_type, path, errors) do
    {nil, [error(path, "must be an object") | errors]}
  end

  defp validate_questionnaire(nil, _task_type, _path, errors), do: errors

  defp validate_questionnaire(questionnaire_key, task_type, path, errors) do
    case Questionnaires.fetch(questionnaire_key) do
      :error ->
        [error(path, "is not a known questionnaire") | errors]

      {:ok, questionnaire} ->
        if questionnaire.task_type() == task_type do
          errors
        else
          [error(path, "is not compatible with #{task_type}") | errors]
        end
    end
  end

  defp validate_stimuli(nil, _task_type, _path, errors), do: errors

  defp validate_stimuli(stimuli, task_type, path, errors) do
    Enum.reduce(Task.stimuli_errors(stimuli, task_type), errors, fn {relative_path, message},
                                                                    errors ->
      error_path = if relative_path == "", do: path, else: "#{path}.#{relative_path}"
      [error(error_path, message) | errors]
    end)
  end

  defp task_type(condition, path, errors) do
    case Map.get(condition, "task_type") do
      "comparison" ->
        {:comparison, errors}

      "binary_question" ->
        {:binary_question, errors}

      nil ->
        {nil, [error("#{path}.task_type", "is required") | errors]}

      _other ->
        {nil, [error("#{path}.task_type", "must be comparison or binary_question") | errors]}
    end
  end

  defp required_string(map, key, path, errors) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        if String.trim(value) == "" do
          {nil, [error(path, "must not be blank") | errors]}
        else
          {value, errors}
        end

      nil ->
        {nil, [error(path, "is required") | errors]}

      _other ->
        {nil, [error(path, "must be a string") | errors]}
    end
  end

  defp required_map(map, key, path, errors) do
    case Map.get(map, key) do
      value when is_map(value) -> {value, errors}
      nil -> {nil, [error(path, "is required") | errors]}
      _other -> {nil, [error(path, "must be an object") | errors]}
    end
  end

  defp optional_string(map, key, parent_path, errors) do
    case Map.fetch(map, key) do
      :error ->
        {nil, errors}

      {:ok, value} when is_binary(value) ->
        case String.trim(value) do
          "" -> {nil, [error("#{parent_path}.#{key}", "must not be blank") | errors]}
          normalized -> {normalized, errors}
        end

      {:ok, _value} ->
        {nil, [error("#{parent_path}.#{key}", "must be a string") | errors]}
    end
  end

  defp validate_instructions_key(nil, _path, errors), do: errors

  defp validate_instructions_key(instructions_key, path, errors) do
    case Instructions.fetch(instructions_key) do
      {:ok, _instruction_set} -> errors
      :error -> [error(path, "is not a known instruction set") | errors]
    end
  end

  defp required_non_empty_list(map, key, path, errors) do
    case Map.get(map, key) do
      [_item | _rest] = value -> {value, errors}
      [] -> {nil, [error(path, "must not be empty") | errors]}
      nil -> {nil, [error(path, "is required") | errors]}
      _other -> {nil, [error(path, "must be an array") | errors]}
    end
  end

  defp positive_integer(map, key, path, errors) do
    case Map.get(map, key) do
      value when is_integer(value) and value > 0 -> {value, errors}
      nil -> {nil, [error(path, "is required") | errors]}
      _other -> {nil, [error(path, "must be a positive integer") | errors]}
    end
  end

  defp unknown_key_errors(map, allowed_keys, path) do
    map
    |> Map.keys()
    |> Enum.reject(&(&1 in allowed_keys))
    |> Enum.sort()
    |> Enum.map(&error("#{path}.#{&1}", "is not allowed"))
  end

  defp duplicate_errors(items, key, path, errors) do
    items
    |> Enum.with_index()
    |> Enum.reduce({MapSet.new(), errors}, fn {item, index}, {seen, errors} ->
      value = Map.fetch!(item, key)

      if MapSet.member?(seen, value) do
        field = if key == :external_key, do: "key", else: Atom.to_string(key)
        {seen, [error("#{path}[#{index}].#{field}", "is duplicated in this manifest") | errors]}
      else
        {MapSet.put(seen, value), errors}
      end
    end)
    |> elem(1)
  end

  defp contiguous_position_errors(items, path, errors) do
    indexed_positions =
      items
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {%{"position" => position}, index} when is_integer(position) and position > 0 ->
          [{position, index}]

        _item ->
          []
      end)

    positions = Enum.map(indexed_positions, &elem(&1, 0))

    if length(indexed_positions) == length(items) and
         length(positions) == MapSet.size(MapSet.new(positions)) do
      indexed_positions
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.with_index(1)
      |> Enum.reduce(errors, fn {{position, source_index}, expected_position}, errors ->
        if position == expected_position do
          errors
        else
          [error("#{path}[#{source_index}].position", "must be #{expected_position}") | errors]
        end
      end)
    else
      errors
    end
  end

  defp error(path, message), do: %ImportError{path: path, message: message}
end
