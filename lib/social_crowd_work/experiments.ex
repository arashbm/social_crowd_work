defmodule SocialCrowdWork.Experiments do
  @moduledoc """
  Manages the immutable experimental design imported for data collection.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias SocialCrowdWork.Experiments.{Condition, ImportBatch, Run, Task}
  alias SocialCrowdWork.Repo

  def create_condition(attrs) do
    attrs = put_default(attrs, :entry_token, &generate_entry_token/0)

    %Condition{}
    |> Condition.changeset(attrs)
    |> Repo.insert()
  end

  def create_import_batch(attrs) do
    attrs = put_default(attrs, :imported_at, &now/0)

    %ImportBatch{}
    |> ImportBatch.changeset(attrs)
    |> Repo.insert()
  end

  def configure_condition(%Condition{} = condition, attrs) do
    condition
    |> Condition.operational_changeset(attrs)
    |> Repo.update()
  end

  def get_condition(id), do: Repo.get(Condition, id)

  def get_condition_by_key(key) when is_binary(key), do: Repo.get_by(Condition, key: key)
  def get_condition_by_key(_key), do: nil

  def get_condition_by_entry_token(entry_token) when is_binary(entry_token) do
    Repo.get_by(Condition, entry_token: entry_token)
  end

  def get_condition_by_entry_token(_entry_token), do: nil

  def create_run_with_tasks(%Condition{} = condition, attrs) do
    tasks = Map.get(attrs, :tasks, [])

    if tasks == [] do
      {:error, :tasks_required}
    else
      Repo.transaction(fn ->
        run_attrs =
          attrs
          |> Map.delete(:tasks)
          |> Map.put(:condition_id, condition.id)

        with {:ok, run} <- Repo.insert(Run.changeset(%Run{}, run_attrs)),
             {:ok, inserted_tasks} <- insert_tasks(run, tasks, condition.task_type) do
          %{run | tasks: inserted_tasks}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  def get_task_by_position(run_id, position) do
    Repo.get_by(Task, run_id: run_id, position: position)
  end

  def list_run_tasks(run_id) do
    Task
    |> where([task], task.run_id == ^run_id)
    |> order_by([task], asc: task.position)
    |> Repo.all()
  end

  defp insert_tasks(run, task_attrs, task_type) do
    task_attrs
    |> Enum.reduce_while({:ok, []}, fn attrs, {:ok, tasks} ->
      changeset =
        %Task{}
        |> Task.changeset(Map.put(attrs, :run_id, run.id), task_type)

      case Repo.insert(changeset) do
        {:ok, task} -> {:cont, {:ok, [task | tasks]}}
        {:error, %Changeset{} = changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, tasks} -> {:ok, Enum.reverse(tasks)}
      error -> error
    end
  end

  defp generate_entry_token do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp put_default(attrs, key, default_fun) do
    if Map.get(attrs, key) do
      attrs
    else
      Map.put(attrs, key, default_fun.())
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
