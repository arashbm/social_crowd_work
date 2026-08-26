defmodule SocialCrowdWork.AdminPanel do
  @moduledoc """
  Read models and operational commands used by the authenticated admin panel.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias SocialCrowdWork.Admins.Scope
  alias SocialCrowdWork.DataCollection.{Participation, Response}
  alias SocialCrowdWork.Experiments
  alias SocialCrowdWork.Experiments.{Condition, ImportBatch, Run, Task}
  alias SocialCrowdWork.Imports
  alias SocialCrowdWork.Questionnaires
  alias SocialCrowdWork.Repo

  def dashboard_stats(%Scope{}) do
    assigned_run_ids = from(participation in Participation, select: participation.run_id)

    %{
      conditions: Repo.aggregate(Condition, :count),
      active_conditions:
        Repo.aggregate(from(condition in Condition, where: condition.status == :active), :count),
      imports: Repo.aggregate(ImportBatch, :count),
      runs: Repo.aggregate(Run, :count),
      available_runs:
        Repo.aggregate(from(run in Run, where: run.id not in subquery(assigned_run_ids)), :count),
      in_progress:
        Repo.aggregate(
          from(participation in Participation,
            where: participation.status in [:assigned, :in_progress]
          ),
          :count
        ),
      completed:
        Repo.aggregate(
          from(participation in Participation, where: participation.status == :completed),
          :count
        )
    }
  end

  def list_condition_summaries(%Scope{}) do
    Condition
    |> order_by([condition], asc: condition.key)
    |> Repo.all()
    |> Enum.map(&condition_summary/1)
  end

  def get_condition_summary!(%Scope{}, id) do
    Condition
    |> Repo.get!(id)
    |> condition_summary()
  end

  def change_condition(%Scope{}, %Condition{} = condition, attrs \\ %{}) do
    Condition.changeset(condition, attrs)
  end

  def configure_condition(%Scope{}, %Condition{} = condition, attrs) do
    Experiments.configure_condition(condition, attrs)
  end

  def import_manifest(%Scope{}, contents, opts) do
    Imports.import_manifest(contents, opts)
  end

  def set_condition_status(%Scope{}, %Condition{} = condition, status) do
    changeset = Condition.changeset(condition, %{status: status})

    changeset =
      if status == :active and
           Repo.aggregate(from(run in Run, where: run.condition_id == ^condition.id), :count) == 0 do
        Changeset.add_error(changeset, :status, "cannot be active without imported runs")
      else
        changeset
      end

    Repo.update(changeset)
  end

  def list_import_summaries(%Scope{}) do
    ImportBatch
    |> order_by([batch], desc: batch.imported_at, desc: batch.id)
    |> Repo.all()
    |> Enum.map(fn batch ->
      runs = Repo.aggregate(from(run in Run, where: run.import_batch_id == ^batch.id), :count)

      tasks =
        Repo.aggregate(
          from(task in Task,
            join: run in Run,
            on: run.id == task.run_id,
            where: run.import_batch_id == ^batch.id
          ),
          :count
        )

      %{batch: batch, runs: runs, tasks: tasks}
    end)
  end

  def list_run_summaries(%Scope{}, condition_id, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.fetch!(opts, :offset)

    paged_runs =
      from(run in Run,
        where: run.condition_id == ^condition_id,
        order_by: [asc: run.external_key],
        limit: ^limit,
        offset: ^offset,
        select: %{id: run.id, external_key: run.external_key}
      )

    from(run in subquery(paged_runs),
      left_join: task in Task,
      on: task.run_id == run.id,
      left_join: participation in Participation,
      on: participation.run_id == run.id,
      group_by: [run.id, run.external_key, participation.status],
      order_by: [asc: run.external_key],
      select: %{
        id: run.id,
        external_key: run.external_key,
        task_count: count(task.id),
        participation_status: participation.status
      }
    )
    |> Repo.all()
  end

  def get_run!(%Scope{}, id) do
    Run
    |> Repo.get!(id)
    |> Repo.preload([:condition, :import_batch, :participation, tasks: :responses])
  end

  def list_participations(%Scope{}) do
    Participation
    |> order_by([participation], desc: participation.started_at, desc: participation.id)
    |> preload([:responses, run: [:condition, :tasks]])
    |> Repo.all()
  end

  def get_participation!(%Scope{}, id) do
    Participation
    |> Repo.get!(id)
    |> Repo.preload(run: :condition)
  end

  def get_participation(%Scope{}, id) do
    Participation
    |> preload(run: :condition)
    |> Repo.get(id)
  end

  def count_participation_tasks(%Scope{}, %Participation{run_id: run_id}) do
    Repo.aggregate(from(task in Task, where: task.run_id == ^run_id), :count)
  end

  def list_participation_task_page(%Scope{}, %Participation{} = participation, opts) do
    limit = Keyword.fetch!(opts, :limit)
    offset = Keyword.fetch!(opts, :offset)

    tasks =
      Task
      |> where([task], task.run_id == ^participation.run_id)
      |> order_by([task], asc: task.position)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    task_ids = Enum.map(tasks, & &1.id)

    responses =
      Response
      |> where(
        [response],
        response.participation_id == ^participation.id and response.task_id in ^task_ids
      )
      |> Repo.all()

    %{tasks: tasks, responses: responses}
  end

  def participation_progress(%Participation{} = participation) do
    expected_pairs =
      participation.run.tasks
      |> Enum.flat_map(fn task ->
        questionnaire = Questionnaires.fetch!(task.questionnaire_key)
        Enum.map(questionnaire.questions(), &{task.id, &1.key()})
      end)
      |> MapSet.new()

    answered_pairs =
      participation.responses
      |> Enum.map(&{&1.task_id, &1.question_key})
      |> MapSet.new()
      |> MapSet.intersection(expected_pairs)

    %{answered: MapSet.size(answered_pairs), expected: MapSet.size(expected_pairs)}
  end

  defp condition_summary(condition) do
    total_runs =
      Repo.aggregate(from(run in Run, where: run.condition_id == ^condition.id), :count)

    assigned_runs =
      Repo.aggregate(
        from(participation in Participation,
          join: run in Run,
          on: run.id == participation.run_id,
          where: run.condition_id == ^condition.id
        ),
        :count
      )

    completed_runs =
      Repo.aggregate(
        from(participation in Participation,
          join: run in Run,
          on: run.id == participation.run_id,
          where: run.condition_id == ^condition.id and participation.status == :completed
        ),
        :count
      )

    %{
      condition: condition,
      total_runs: total_runs,
      available_runs: total_runs - assigned_runs,
      assigned_runs: assigned_runs,
      completed_runs: completed_runs
    }
  end
end
