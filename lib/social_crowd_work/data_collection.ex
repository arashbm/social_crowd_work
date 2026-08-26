defmodule SocialCrowdWork.DataCollection do
  @moduledoc """
  Assigns imported runs to participants and records their answers.
  """

  import Ecto.Query

  alias SocialCrowdWork.Consents
  alias SocialCrowdWork.DataCollection.{ParticipantLaunch, Participation, Response}
  alias SocialCrowdWork.Experiments.{Condition, Run, Task}
  alias SocialCrowdWork.Instructions
  alias SocialCrowdWork.ParticipantEvents
  alias SocialCrowdWork.Questionnaires
  alias SocialCrowdWork.Repo

  def create_participant_launch(%Condition{id: condition_id}, attrs) do
    Repo.transaction(fn ->
      current_time = now()

      ParticipantLaunch
      |> where([launch], launch.expires_at <= ^current_time)
      |> Repo.delete_all()

      lock_prolific_session!(Map.get(attrs, :prolific_session_id))
      condition = Repo.get!(Condition, condition_id)

      participation =
        case participation_for_session(Map.get(attrs, :prolific_session_id)) do
          %Participation{} = participation ->
            resume_for_condition(participation, condition, attrs)

          nil ->
            validate_launch!(condition, attrs)
            nil
        end

      {raw_token, token_hash} = ParticipantLaunch.generate_token()

      launch_attrs =
        Map.put(
          attrs,
          :expires_at,
          DateTime.add(current_time, launch_ttl(launch_state(participation)), :second)
        )

      case Repo.insert(
             ParticipantLaunch.create_changeset(
               condition,
               participation,
               token_hash,
               launch_attrs
             )
           ) do
        {:ok, _launch} -> raw_token
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  def create_participant_resume_launch(
        %Participation{
          status: status,
          run: %Run{condition: %Condition{} = condition}
        } = participation
      )
      when status in [:assigned, :in_progress] do
    create_participant_launch(condition, launch_identity(participation))
  end

  def create_participant_resume_launch(%Participation{}),
    do: {:error, :participation_not_resumable}

  def resolve_participant_launch(raw_token) do
    current_time = now()

    with {:ok, token_hash} <- ParticipantLaunch.hash_token(raw_token),
         %ParticipantLaunch{} = launch <-
           ParticipantLaunch
           |> where(
             [launch],
             launch.token_hash == ^token_hash and launch.expires_at > ^current_time
           )
           |> preload([:condition, :participation])
           |> Repo.one() do
      {:ok, %{launch: launch, condition: launch.condition, participation: launch.participation}}
    else
      _other -> {:error, :invalid_launch}
    end
  end

  def consent_and_assign_run(raw_token, consent_key) when is_binary(raw_token) do
    with {:ok, token_hash} <- ParticipantLaunch.hash_token(raw_token) do
      Repo.transaction(fn ->
        launch = lock_valid_launch!(token_hash)
        lock_prolific_session!(launch.prolific_session_id)
        condition = Repo.get!(Condition, launch.condition_id)
        attrs = launch_identity(launch)

        participation = consent_and_assign_run!(condition, attrs, consent_key)

        launch
        |> Ecto.Changeset.change(
          participation_id: participation.id,
          expires_at: DateTime.add(now(), launch_ttl(:post_consent), :second)
        )
        |> Repo.update!()

        participation
      end)
    else
      :error -> {:error, :invalid_launch}
    end
  end

  def consent_and_assign_run(_raw_token, _consent_key), do: {:error, :invalid_launch}

  def consent_and_assign_run(%Condition{id: condition_id}, attrs, consent_key) do
    Repo.transaction(fn ->
      lock_prolific_session!(Map.get(attrs, :prolific_session_id))
      condition = Repo.get!(Condition, condition_id)

      consent_and_assign_run!(condition, attrs, consent_key)
    end)
  end

  def decline_participant_launch(raw_token) do
    with {:ok, token_hash} <- ParticipantLaunch.hash_token(raw_token) do
      case Repo.transaction(fn ->
             launch = lock_valid_launch!(token_hash)

             if launch.participation_id do
               Repo.rollback(:already_consented)
             else
               Repo.delete!(launch)
             end
           end) do
        {:ok, launch} -> {:ok, launch}
        {:error, reason} -> {:error, reason}
      end
    else
      :error -> {:error, :invalid_launch}
    end
  end

  def complete_participant_launch(raw_token) do
    with {:ok, token_hash} <- ParticipantLaunch.hash_token(raw_token) do
      Repo.transaction(fn ->
        launch = lock_valid_launch!(token_hash)
        participation = exact_launch_participation!(launch)

        if participation.status != :completed do
          Repo.rollback(:participation_not_completed)
        end

        condition = Repo.get!(Condition, launch.condition_id)

        ParticipantLaunch
        |> where([stored], stored.participation_id == ^participation.id)
        |> Repo.delete_all()

        %{condition: condition, completion_code: condition.prolific_completion_code}
      end)
    else
      :error -> {:error, :invalid_launch}
    end
  end

  defp consent_and_assign_run!(condition, attrs, consent_key) do
    case participation_for_session(Map.get(attrs, :prolific_session_id)) do
      %Participation{} = participation ->
        resume_for_condition(participation, condition, attrs)

      nil ->
        validate_new_participation!(condition, attrs, consent_key)
        assign_available_run(condition, attrs, consent_key)
    end
  end

  def resume_participation(%Condition{} = condition, attrs) do
    case participation_for_session(Map.get(attrs, :prolific_session_id)) do
      nil ->
        {:error, :not_found}

      participation ->
        Repo.transaction(fn -> resume_for_condition(participation, condition, attrs) end)
    end
  end

  def instruction_page(%Participation{id: participation_id}) do
    case Repo.get(Participation, participation_id) do
      nil ->
        {:error, :not_found}

      participation ->
        instruction_page_for(participation)
    end
  end

  def advance_instruction_page(
        %Participation{id: participation_id},
        submitted_page_number
      )
      when is_integer(submitted_page_number) and submitted_page_number > 0 do
    Repo.transaction(fn ->
      participation =
        Participation
        |> where([participation], participation.id == ^participation_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if participation.status == :completed do
        Repo.rollback(:participation_completed)
      end

      advance_instruction_page!(participation, submitted_page_number)
    end)
  end

  def advance_instruction_page(%Participation{}, _submitted_page_number) do
    {:error, :instruction_page_out_of_order}
  end

  def record_response(%Participation{id: participation_id}, task_id, question_key, choice) do
    Repo.transaction(fn ->
      participation =
        Participation
        |> where([participation], participation.id == ^participation_id)
        |> lock("FOR UPDATE")
        |> Repo.one!()

      if participation.status == :completed do
        Repo.rollback(:participation_completed)
      end

      if not instructions_complete?(participation) do
        Repo.rollback(:instructions_incomplete)
      end

      case task_with_type(task_id, participation.run_id) do
        nil ->
          Repo.rollback(:task_not_in_run)

        {task, task_type} ->
          question = question_for_task!(task, question_key)

          if choice not in question.choices() do
            Repo.rollback(:choice_not_allowed)
          end

          attrs = %{
            participation_id: participation.id,
            task_id: task.id,
            run_id: participation.run_id,
            question_key: question.key(),
            choice: choice,
            answered_at: now()
          }

          response =
            Repo.get_by(Response,
              participation_id: participation.id,
              task_id: task.id,
              question_key: question.key()
            )

          case persist_response(response, attrs, task_type) do
            {:ok, response, previous_choice} ->
              if previous_choice != choice do
                ParticipantEvents.insert_answer_event!(
                  participation,
                  task,
                  question.key(),
                  previous_choice,
                  choice
                )
              end

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

    case task do
      nil ->
        {:error, :not_found}

      task ->
        with {:ok, questionnaire} <- Questionnaires.fetch(task.questionnaire_key) do
          total_tasks =
            Task
            |> where([stored_task], stored_task.run_id == ^participation.run_id)
            |> Repo.aggregate(:count)

          responses =
            Response
            |> where(
              [response],
              response.participation_id == ^participation.id and response.task_id == ^task.id
            )
            |> Repo.all()

          responses_by_key = Map.new(responses, &{&1.question_key, &1})

          questions =
            questionnaire.questions()
            |> Enum.with_index(1)
            |> Enum.map(fn {module, number} ->
              %{
                number: number,
                key: module.key(),
                module: module,
                response: Map.get(responses_by_key, module.key())
              }
            end)

          expected_keys = MapSet.new(questions, & &1.key)
          actual_keys = MapSet.new(responses, & &1.question_key)

          {:ok,
           %{
             task: task,
             questionnaire: questionnaire,
             questions: questions,
             active_question_key: first_unanswered_key(questions),
             complete?: expected_keys == actual_keys,
             total_tasks: total_tasks
           }}
        else
          :error -> {:error, :unknown_questionnaire}
        end
    end
  end

  def task_page(%Participation{}, _position), do: {:error, :not_found}

  def next_incomplete_task(%Participation{} = participation) do
    tasks =
      Task
      |> where([task], task.run_id == ^participation.run_id)
      |> order_by([task], asc: task.position)
      |> Repo.all()

    response_identities = response_identities(participation)

    Enum.find(tasks, fn task ->
      case expected_question_keys(task) do
        {:ok, expected_keys} ->
          Map.get(response_identities, task.id, MapSet.new()) != expected_keys

        :error ->
          true
      end
    end)
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
        |> Map.put(:instructions_key, condition.instructions_key)
        |> Map.put(:instruction_pages_completed, 0)
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

  defp validate_launch!(condition, attrs) do
    cond do
      condition.status != :active -> Repo.rollback(:condition_inactive)
      prolific_study_mismatch?(condition, attrs) -> Repo.rollback(:prolific_study_mismatch)
      true -> :ok
    end
  end

  defp lock_valid_launch!(token_hash) do
    launch =
      ParticipantLaunch
      |> where([stored], stored.token_hash == ^token_hash)
      |> lock("FOR UPDATE")
      |> Repo.one()

    if is_nil(launch) or ParticipantLaunch.expired?(launch, now()) do
      Repo.rollback(:invalid_launch)
    end

    launch
  end

  defp exact_launch_participation!(%ParticipantLaunch{participation_id: nil}) do
    Repo.rollback(:invalid_launch)
  end

  defp exact_launch_participation!(launch) do
    participation =
      from(participation in Participation,
        join: run in Run,
        on: run.id == participation.run_id,
        where:
          participation.id == ^launch.participation_id and
            run.condition_id == ^launch.condition_id and
            participation.prolific_participant_id == ^launch.prolific_participant_id and
            participation.prolific_study_id == ^launch.prolific_study_id and
            participation.prolific_session_id == ^launch.prolific_session_id,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    participation || Repo.rollback(:invalid_launch)
  end

  defp launch_identity(launch) do
    %{
      prolific_participant_id: launch.prolific_participant_id,
      prolific_study_id: launch.prolific_study_id,
      prolific_session_id: launch.prolific_session_id
    }
  end

  defp launch_state(nil), do: :pre_consent
  defp launch_state(%Participation{}), do: :post_consent

  defp launch_ttl(:pre_consent) do
    Application.fetch_env!(:social_crowd_work, :participant_launch_pre_consent_ttl_seconds)
  end

  defp launch_ttl(:post_consent) do
    Application.fetch_env!(:social_crowd_work, :participant_launch_post_consent_ttl_seconds)
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

  defp question_for_task!(task, question_key) do
    questionnaire =
      case Questionnaires.fetch(task.questionnaire_key) do
        {:ok, questionnaire} -> questionnaire
        :error -> Repo.rollback(:unknown_questionnaire)
      end

    case Enum.find(questionnaire.questions(), &(&1.key() == question_key)) do
      nil -> Repo.rollback(:question_not_in_questionnaire)
      question -> question
    end
  end

  defp mark_in_progress(%Participation{status: :assigned} = participation) do
    participation
    |> Participation.changeset(%{status: :in_progress})
    |> Repo.update!()
  end

  defp mark_in_progress(_participation), do: :ok

  defp instruction_page_for(%Participation{instructions_key: nil}), do: {:ok, :complete}

  defp instruction_page_for(%Participation{} = participation) do
    with {:ok, instruction_set} <- Instructions.fetch(participation.instructions_key) do
      pages = instruction_set.pages()

      case Enum.at(pages, participation.instruction_pages_completed) do
        nil ->
          {:ok, :complete}

        page ->
          {:ok,
           %{
             instruction_set: instruction_set,
             page: page,
             page_number: participation.instruction_pages_completed + 1,
             total_pages: length(pages)
           }}
      end
    else
      :error -> {:error, :unknown_instruction_set}
    end
  end

  defp advance_instruction_page!(%Participation{instructions_key: nil}, _page_number) do
    Repo.rollback(:instruction_page_out_of_order)
  end

  defp advance_instruction_page!(participation, submitted_page_number) do
    case Instructions.fetch(participation.instructions_key) do
      {:ok, instruction_set} ->
        completed = participation.instruction_pages_completed
        total_pages = length(instruction_set.pages())

        cond do
          submitted_page_number <= completed ->
            participation

          submitted_page_number == completed + 1 and submitted_page_number <= total_pages ->
            page = Enum.at(instruction_set.pages(), submitted_page_number - 1)
            attrs = %{instruction_pages_completed: submitted_page_number}

            attrs =
              if submitted_page_number == total_pages do
                Map.put(attrs, :instructions_completed_at, now())
              else
                attrs
              end

            participation =
              participation
              |> Participation.changeset(attrs)
              |> Repo.update!()

            kind =
              if submitted_page_number == total_pages,
                do: :instructions_completed,
                else: :instruction_page_advanced

            ParticipantEvents.insert_instruction_progress_event!(
              participation,
              kind,
              page.key(),
              submitted_page_number
            )

            participation

          true ->
            Repo.rollback(:instruction_page_out_of_order)
        end

      :error ->
        Repo.rollback(:unknown_instruction_set)
    end
  end

  defp instructions_complete?(%Participation{instructions_key: nil}), do: true

  defp instructions_complete?(%Participation{instructions_completed_at: completed_at}) do
    not is_nil(completed_at)
  end

  defp persist_response(nil, attrs, task_type) do
    case %Response{} |> Response.changeset(attrs, task_type) |> Repo.insert() do
      {:ok, response} -> {:ok, response, nil}
      error -> error
    end
  end

  defp persist_response(%Response{choice: choice} = response, %{choice: choice}, _task_type) do
    {:ok, response, choice}
  end

  defp persist_response(%Response{} = response, attrs, task_type) do
    previous_choice = response.choice

    case response |> Response.changeset(attrs, task_type) |> Repo.update() do
      {:ok, response} -> {:ok, response, previous_choice}
      error -> error
    end
  end

  defp complete_if_answered(participation) do
    tasks =
      Task
      |> where([task], task.run_id == ^participation.run_id)
      |> Repo.all()

    actual_identities = response_identities(participation)

    expected_identities =
      Enum.reduce(tasks, %{}, fn task, identities ->
        case expected_question_keys(task) do
          {:ok, question_keys} -> Map.put(identities, task.id, question_keys)
          :error -> Repo.rollback(:unknown_questionnaire)
        end
      end)

    if tasks != [] and actual_identities == expected_identities do
      participation
      |> Participation.changeset(%{status: :completed, completed_at: now()})
      |> Repo.update!()
    else
      Repo.rollback(:tasks_remaining)
    end
  end

  defp expected_question_keys(task) do
    case Questionnaires.fetch(task.questionnaire_key) do
      {:ok, questionnaire} -> {:ok, MapSet.new(questionnaire.questions(), & &1.key())}
      :error -> :error
    end
  end

  defp response_identities(participation) do
    from(response in Response,
      join: task in Task,
      on: task.id == response.task_id,
      where:
        response.participation_id == ^participation.id and
          task.run_id == ^participation.run_id,
      select: {response.task_id, response.question_key}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {task_id, question_keys} -> {task_id, MapSet.new(question_keys)} end)
  end

  defp first_unanswered_key(questions) do
    case Enum.find(questions, &is_nil(&1.response)) do
      nil -> nil
      question -> question.key
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
