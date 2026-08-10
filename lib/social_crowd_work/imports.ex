defmodule SocialCrowdWork.Imports do
  @moduledoc """
  Validates and transactionally imports versioned experiment manifests.

  This service accepts file contents rather than paths so command-line and web
  upload callers use exactly the same validation and persistence code.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias SocialCrowdWork.Experiments
  alias SocialCrowdWork.Experiments.{Condition, ImportBatch, Run, Task}
  alias SocialCrowdWork.Imports.{ImportError, ImportResult, Manifest}
  alias SocialCrowdWork.Repo

  def import_manifest(contents, opts \\ []) when is_binary(contents) do
    source_sha256 = sha256(contents)
    filename = opts |> Keyword.get(:filename, "upload.json") |> Path.basename()
    dry_run? = Keyword.get(opts, :dry_run, false)

    case Repo.get_by(ImportBatch, source_sha256: source_sha256) do
      %ImportBatch{} = import_batch ->
        {:ok, result_for_batch(import_batch, :already_imported)}

      nil ->
        with {:ok, plan} <- Manifest.validate(contents),
             :ok <- validate_against_database(plan) do
          if dry_run? do
            {:ok, result_for_plan(plan, :validated)}
          else
            persist(plan, filename, source_sha256)
          end
        end
    end
  end

  def validate_manifest(contents) when is_binary(contents), do: Manifest.validate(contents)

  defp persist(plan, filename, source_sha256) do
    case Repo.transaction(fn ->
           lock!("import-file:#{source_sha256}")
           Enum.each(Enum.sort_by(plan.conditions, & &1.key), &lock!("condition:#{&1.key}"))

           case Repo.get_by(ImportBatch, source_sha256: source_sha256) do
             %ImportBatch{} = import_batch ->
               result_for_batch(import_batch, :already_imported)

             nil ->
               persist_new_import(plan, filename, source_sha256)
           end
         end) do
      {:ok, %ImportResult{} = result} -> {:ok, result}
      {:error, errors} when is_list(errors) -> {:error, errors}
      {:error, reason} -> {:error, [error("$", "could not import manifest: #{inspect(reason)}")]}
    end
  end

  defp persist_new_import(plan, filename, source_sha256) do
    case validate_against_database(plan) do
      :ok ->
        import_batch = insert_import_batch!(plan, filename, source_sha256)
        insert_conditions_and_runs!(plan, import_batch)
        result_for_batch(import_batch, :imported)

      {:error, errors} ->
        Repo.rollback(errors)
    end
  end

  defp insert_import_batch!(plan, filename, source_sha256) do
    attrs = %{
      original_filename: filename,
      source_sha256: source_sha256,
      format_version: plan.format_version
    }

    case Experiments.create_import_batch(attrs) do
      {:ok, import_batch} -> import_batch
      {:error, changeset} -> Repo.rollback(changeset_errors(changeset, "import_batch"))
    end
  end

  defp insert_conditions_and_runs!(plan, import_batch) do
    Enum.each(plan.conditions, fn condition_plan ->
      condition = get_or_create_condition!(condition_plan)

      condition_plan.runs
      |> Enum.with_index()
      |> Enum.each(fn {run_plan, run_index} ->
        attrs = %{
          import_batch_id: import_batch.id,
          external_key: run_plan.external_key,
          tasks: run_plan.tasks
        }

        case Experiments.create_run_with_tasks(condition, attrs) do
          {:ok, _run} ->
            :ok

          {:error, %Changeset{} = changeset} ->
            path = condition_run_path(plan, condition_plan.key, run_index)
            Repo.rollback(changeset_errors(changeset, path))

          {:error, reason} ->
            path = condition_run_path(plan, condition_plan.key, run_index)
            Repo.rollback([error(path, "could not be imported: #{inspect(reason)}")])
        end
      end)
    end)
  end

  defp get_or_create_condition!(condition_plan) do
    case Repo.get_by(Condition, key: condition_plan.key) do
      %Condition{} = condition ->
        condition

      nil ->
        attrs = %{
          key: condition_plan.key,
          task_type: condition_plan.task_type,
          variants: condition_plan.variants,
          status: :draft
        }

        case Experiments.create_condition(attrs) do
          {:ok, condition} -> condition
          {:error, changeset} -> Repo.rollback(changeset_errors(changeset, "conditions"))
        end
    end
  end

  defp validate_against_database(plan) do
    condition_keys = Enum.map(plan.conditions, & &1.key)

    existing_conditions =
      Condition
      |> where([condition], condition.key in ^condition_keys)
      |> Repo.all()
      |> Map.new(&{&1.key, &1})

    errors =
      plan.conditions
      |> Enum.with_index()
      |> Enum.reduce([], fn {condition_plan, condition_index}, errors ->
        case Map.get(existing_conditions, condition_plan.key) do
          nil ->
            errors

          condition ->
            errors
            |> condition_consistency_errors(condition_plan, condition, condition_index)
            |> existing_run_errors(condition_plan, condition, condition_index)
        end
      end)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  defp condition_consistency_errors(errors, plan, condition, index) do
    errors =
      if plan.task_type == condition.task_type do
        errors
      else
        [
          error("conditions[#{index}].task_type", "does not match the existing condition")
          | errors
        ]
      end

    if plan.variants == condition.variants do
      errors
    else
      [error("conditions[#{index}].variants", "do not match the existing condition") | errors]
    end
  end

  defp existing_run_errors(errors, condition_plan, condition, condition_index) do
    run_keys = Enum.map(condition_plan.runs, & &1.external_key)

    existing_keys =
      Run
      |> where([run], run.condition_id == ^condition.id and run.external_key in ^run_keys)
      |> select([run], run.external_key)
      |> Repo.all()
      |> MapSet.new()

    condition_plan.runs
    |> Enum.with_index()
    |> Enum.reduce(errors, fn {run, run_index}, errors ->
      if MapSet.member?(existing_keys, run.external_key) do
        path = "conditions[#{condition_index}].runs[#{run_index}].key"
        [error(path, "already exists for this condition") | errors]
      else
        errors
      end
    end)
  end

  defp result_for_plan(plan, status) do
    %ImportResult{
      status: status,
      import_batch: nil,
      condition_count: length(plan.conditions),
      run_count: Enum.sum(Enum.map(plan.conditions, &length(&1.runs))),
      task_count:
        Enum.sum(
          for condition <- plan.conditions,
              run <- condition.runs,
              do: length(run.tasks)
        )
    }
  end

  defp result_for_batch(import_batch, status) do
    run_query = from run in Run, where: run.import_batch_id == ^import_batch.id

    condition_count =
      from(run in run_query, select: count(run.condition_id, :distinct))
      |> Repo.one()

    run_count = Repo.aggregate(run_query, :count)

    task_count =
      from(task in Task,
        join: run in Run,
        on: run.id == task.run_id,
        where: run.import_batch_id == ^import_batch.id
      )
      |> Repo.aggregate(:count)

    %ImportResult{
      status: status,
      import_batch: import_batch,
      condition_count: condition_count,
      run_count: run_count,
      task_count: task_count
    }
  end

  defp condition_run_path(plan, condition_key, run_index) do
    condition_index = Enum.find_index(plan.conditions, &(&1.key == condition_key))
    "conditions[#{condition_index}].runs[#{run_index}]"
  end

  defp changeset_errors(changeset, path) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, &error("#{path}.#{field}", &1))
    end)
  end

  defp lock!(value) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [value])
  end

  defp sha256(contents) do
    :sha256
    |> :crypto.hash(contents)
    |> Base.encode16(case: :lower)
  end

  defp error(path, message), do: %ImportError{path: path, message: message}
end
