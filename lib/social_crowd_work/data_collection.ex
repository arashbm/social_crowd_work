defmodule SocialCrowdWork.DataCollection do
  @moduledoc """
  Assigns imported runs to participants and records their answers.
  """

  import Ecto.Query

  alias SocialCrowdWork.Consents
  alias SocialCrowdWork.DataCollection.{Participation, Response}
  alias SocialCrowdWork.Experiments.{Condition, Run, Task}
  alias SocialCrowdWork.Repo

  def consent_and_assign_run(%Condition{id: condition_id}, attrs, consent_key) do
    Repo.transaction(fn ->
      lock_prolific_session!(Map.get(attrs, :prolific_session_id))
      condition = Repo.get!(Condition, condition_id)

      case participation_for_session(Map.get(attrs, :prolific_session_id)) do
        %Participation{} = participation ->
          resume_for_condition(participation, condition, attrs)

        nil ->
          validate_new_participation!(condition, attrs, consent_key)
          assign_available_run(condition, attrs, consent_key)
      end
    end)
  end

  def resume_participation(%Condition{} = condition, attrs) do
    case participation_for_session(Map.get(attrs, :prolific_session_id)) do
      nil ->
        {:error, :not_found}

      participation ->
        Repo.transaction(fn -> resume_for_condition(participation, condition, attrs) end)
    end
  end

  def record_response(%Participation{id: participation_id}, task_id, choice) do
    Repo.transaction(fn ->
      participation =
        Participation
        |> where([participation], participation.id == ^participation_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if participation.status == :completed do
        Repo.rollback(:participation_completed)
      end

      case task_with_type(task_id, participation.run_id) do
        nil ->
          Repo.rollback(:task_not_in_run)

        {task, task_type} ->
          attrs = %{
            participation_id: participation.id,
            task_id: task.id,
            run_id: participation.run_id,
            choice: choice,
            answered_at: now()
          }

          response = Repo.get_by(Response, participation_id: participation.id, task_id: task.id)

          case persist_response(response, attrs, task_type) do
            {:ok, response} ->
              mark_in_progress(participation)
              response

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
      end
    end)
  end

  def task_page(%Participation{} = participation, position) when is_integer(position) do
    task = Repo.get_by(Task, run_id: participation.run_id, position: position)

    if task do
      response = Repo.get_by(Response, participation_id: participation.id, task_id: task.id)

      total_tasks =
        Task
        |> where([stored_task], stored_task.run_id == ^participation.run_id)
        |> Repo.aggregate(:count)

      {:ok, %{task: task, response: response, total_tasks: total_tasks}}
    else
      {:error, :not_found}
    end
  end

  def task_page(%Participation{}, _position), do: {:error, :not_found}

  def next_unanswered_task(%Participation{} = participation) do
    answered_task_ids =
      from response in Response,
        where: response.participation_id == ^participation.id,
        select: response.task_id

    Task
    |> where([task], task.run_id == ^participation.run_id)
    |> where([task], task.id not in subquery(answered_task_ids))
    |> order_by([task], asc: task.position)
    |> limit(1)
    |> Repo.one()
  end

  def complete_participation(%Participation{id: participation_id}) do
    Repo.transaction(fn ->
      participation =
        Participation
        |> where([participation], participation.id == ^participation_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if participation.status == :completed do
        participation
      else
        complete_if_answered(participation)
      end
    end)
  end

  defp assign_available_run(condition, attrs, consent_key) do
    assigned_run_ids = from participation in Participation, select: participation.run_id

    run =
      Run
      |> where([run], run.condition_id == ^condition.id)
      |> where([run], run.id not in subquery(assigned_run_ids))
      |> order_by(fragment("RANDOM()"))
      |> limit(1)
      |> lock("FOR UPDATE SKIP LOCKED")
      |> Repo.one()

    if run do
      accepted_at = now()

      participation_attrs =
        attrs
        |> Map.put(:run_id, run.id)
        |> Map.put(:consent_key, consent_key)
        |> Map.put(:consented_at, accepted_at)
        |> Map.put(:status, :assigned)
        |> Map.put(:started_at, accepted_at)

      case Repo.insert(Participation.changeset(%Participation{}, participation_attrs)) do
        {:ok, participation} -> Repo.preload(participation, run: :condition)
        {:error, changeset} -> Repo.rollback(changeset)
      end
    else
      Repo.rollback(:no_runs_available)
    end
  end

  defp participation_for_session(session_id) when is_binary(session_id) do
    Participation
    |> where([participation], participation.prolific_session_id == ^session_id)
    |> preload(run: :condition)
    |> Repo.one()
  end

  defp participation_for_session(_session_id), do: nil

  defp resume_for_condition(participation, condition, attrs) do
    cond do
      participation.run.condition_id != condition.id ->
        Repo.rollback(:session_condition_mismatch)

      participation.prolific_participant_id != Map.get(attrs, :prolific_participant_id) or
          participation.prolific_study_id != Map.get(attrs, :prolific_study_id) ->
        Repo.rollback(:prolific_identity_mismatch)

      true ->
        participation
    end
  end

  defp prolific_study_mismatch?(%Condition{prolific_study_id: nil}, _attrs), do: false

  defp prolific_study_mismatch?(condition, attrs) do
    Map.get(attrs, :prolific_study_id) != condition.prolific_study_id
  end

  defp validate_new_participation!(condition, attrs, consent_key) do
    cond do
      condition.status != :active ->
        Repo.rollback(:condition_inactive)

      prolific_study_mismatch?(condition, attrs) ->
        Repo.rollback(:prolific_study_mismatch)

      is_nil(condition.consent_key) ->
        Repo.rollback(:consent_not_configured)

      consent_key != condition.consent_key ->
        Repo.rollback(:consent_mismatch)

      Consents.fetch(consent_key) == :error ->
        Repo.rollback(:unknown_consent)

      true ->
        :ok
    end
  end

  defp lock_prolific_session!(session_id) when is_binary(session_id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [session_id])
  end

  defp lock_prolific_session!(_session_id), do: :ok

  defp task_with_type(task_id, run_id) do
    from(task in Task,
      join: run in Run,
      on: run.id == task.run_id,
      join: condition in Condition,
      on: condition.id == run.condition_id,
      where: task.id == ^task_id and task.run_id == ^run_id,
      select: {task, condition.task_type}
    )
    |> Repo.one()
  end

  defp mark_in_progress(%Participation{status: :assigned} = participation) do
    participation
    |> Participation.changeset(%{status: :in_progress})
    |> Repo.update!()
  end

  defp mark_in_progress(_participation), do: :ok

  defp persist_response(nil, attrs, task_type) do
    %Response{}
    |> Response.changeset(attrs, task_type)
    |> Repo.insert()
  end

  defp persist_response(%Response{choice: choice} = response, %{choice: choice}, _task_type) do
    {:ok, response}
  end

  defp persist_response(%Response{} = response, attrs, task_type) do
    response
    |> Response.changeset(attrs, task_type)
    |> Repo.update()
  end

  defp complete_if_answered(participation) do
    task_count =
      Task
      |> where([task], task.run_id == ^participation.run_id)
      |> Repo.aggregate(:count)

    response_count =
      from(response in Response,
        join: task in Task,
        on: task.id == response.task_id,
        where:
          response.participation_id == ^participation.id and
            task.run_id == ^participation.run_id
      )
      |> Repo.aggregate(:count)

    if task_count > 0 and response_count == task_count do
      participation
      |> Participation.changeset(%{status: :completed, completed_at: now()})
      |> Repo.update!()
    else
      Repo.rollback(:tasks_remaining)
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
