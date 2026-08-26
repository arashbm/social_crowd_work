defmodule SocialCrowdWork.DataCollectionTest do
  use SocialCrowdWork.DataCase, async: false

  alias SocialCrowdWork.DataCollection

  alias SocialCrowdWork.DataCollection.{
    ParticipantEvent,
    ParticipantLaunch,
    Participation,
    Response
  }

  alias SocialCrowdWork.Experiments.Condition
  alias SocialCrowdWork.Repo

  import SocialCrowdWork.Fixtures

  describe "consent_and_assign_run/3" do
    test "records consent, assigns an available run, and resumes the same Prolific session" do
      condition = condition_fixture()
      run_fixture(condition)
      attrs = participation_attrs(condition)

      assert {:ok, participation} =
               DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

      assert participation.status == :assigned
      assert participation.prolific_session_id == attrs.prolific_session_id
      assert participation.consent_key == "test-consent.v1"
      assert participation.consented_at
      assert participation.run.condition_id == condition.id

      assert {:ok, resumed} =
               DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

      assert resumed.id == participation.id
      assert {:ok, fetched} = DataCollection.resume_participation(condition, attrs)
      assert fetched.id == participation.id
    end

    test "rejects a changed identity when resuming a session" do
      condition = condition_fixture()
      run_fixture(condition)
      attrs = participation_attrs(condition)

      assert {:ok, _participation} =
               DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

      assert {:error, :prolific_identity_mismatch} =
               DataCollection.consent_and_assign_run(
                 condition,
                 %{attrs | prolific_participant_id: "someone-else"},
                 "test-consent.v1"
               )
    end

    test "does not persist or consume a run when consent is not accepted" do
      condition = condition_fixture()
      run = run_fixture(condition)
      attrs = participation_attrs(condition)

      assert {:error, :consent_mismatch} =
               DataCollection.consent_and_assign_run(condition, attrs, "another-consent.v1")

      assert Repo.aggregate(Participation, :count) == 0

      assert {:ok, participation} =
               DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

      assert participation.run_id == run.id
    end

    test "rejects assignment when a condition has no configured consent" do
      condition = condition_fixture()
      run_fixture(condition)

      Condition
      |> where([stored], stored.id == ^condition.id)
      |> Repo.update_all(set: [consent_key: nil])

      assert {:error, :consent_not_configured} =
               DataCollection.consent_and_assign_run(
                 condition,
                 participation_attrs(condition),
                 "test-consent.v1"
               )

      assert Repo.aggregate(Participation, :count) == 0
    end

    test "allows an accepted participant to resume after recruitment is deactivated" do
      condition = condition_fixture()
      run_fixture(condition)
      attrs = participation_attrs(condition)

      assert {:ok, participation} =
               DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

      assert {:ok, _inactive_condition} =
               SocialCrowdWork.Experiments.configure_condition(condition, %{status: :paused})

      assert {:ok, resumed} =
               DataCollection.consent_and_assign_run(condition, attrs, "outdated-or-missing")

      assert resumed.id == participation.id
    end

    test "rejects inactive conditions and mismatched Prolific studies" do
      inactive_condition = condition_fixture(:comparison, %{status: :paused})
      run_fixture(inactive_condition)

      assert {:error, :condition_inactive} =
               DataCollection.consent_and_assign_run(
                 inactive_condition,
                 participation_attrs(inactive_condition),
                 "test-consent.v1"
               )

      active_condition = condition_fixture()
      run_fixture(active_condition)

      assert {:error, :prolific_study_mismatch} =
               DataCollection.consent_and_assign_run(
                 active_condition,
                 participation_attrs(active_condition, %{prolific_study_id: "wrong-study"}),
                 "test-consent.v1"
               )
    end

    test "returns no_runs_available rather than reusing an assigned run" do
      condition = condition_fixture()
      run_fixture(condition)

      assert {:ok, _participation} =
               DataCollection.consent_and_assign_run(
                 condition,
                 participation_attrs(condition),
                 "test-consent.v1"
               )

      assert {:error, :no_runs_available} =
               DataCollection.consent_and_assign_run(
                 condition,
                 participation_attrs(condition),
                 "test-consent.v1"
               )
    end

    test "concurrent participants receive different runs" do
      condition = condition_fixture()
      run_fixture(condition)
      run_fixture(condition)
      first_attrs = participation_attrs(condition)
      second_attrs = participation_attrs(condition)
      supervisor = start_supervised!(Task.Supervisor)
      parent = self()

      tasks =
        for attrs <- [first_attrs, second_attrs] do
          Task.Supervisor.async_nolink(supervisor, fn ->
            send(parent, {:ready, self()})

            receive do
              :assign ->
                DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")
            end
          end)
        end

      pids =
        for _ <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :assign))

      participations =
        Enum.map(tasks, fn task ->
          assert {:ok, participation} = Task.await(task)
          participation
        end)

      assert participations |> Enum.map(& &1.run_id) |> Enum.uniq() |> length() == 2
    end

    test "concurrent requests for one Prolific session are idempotent" do
      condition = condition_fixture()
      run_fixture(condition)
      attrs = participation_attrs(condition)
      supervisor = start_supervised!(Task.Supervisor)
      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.Supervisor.async_nolink(supervisor, fn ->
            send(parent, {:ready, self()})

            receive do
              :assign ->
                DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")
            end
          end)
        end

      pids =
        for _ <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :assign))

      participation_ids =
        Enum.map(tasks, fn task ->
          assert {:ok, participation} = Task.await(task)
          participation.id
        end)

      assert Enum.uniq(participation_ids) |> length() == 1
      assert Repo.aggregate(Participation, :count) == 1
    end
  end

  describe "instruction progression" do
    setup do
      original_modules =
        Application.get_env(:social_crowd_work, :instruction_set_modules, [])

      Application.put_env(
        :social_crowd_work,
        :instruction_set_modules,
        original_modules ++ [SocialCrowdWork.TwoPageInstructionSet]
      )

      on_exit(fn ->
        Application.put_env(
          :social_crowd_work,
          :instruction_set_modules,
          original_modules
        )
      end)
    end

    test "assignment snapshots the condition instruction set and initializes progress" do
      condition =
        condition_fixture(:comparison, %{instructions_key: "two-page-instructions.v1"})

      run_fixture(condition)
      assert {:ok, participation} = assign(condition)

      assert participation.instructions_key == "two-page-instructions.v1"
      assert participation.instruction_pages_completed == 0
      assert participation.instructions_completed_at == nil

      Condition
      |> where([stored], stored.id == ^condition.id)
      |> Repo.update_all(set: [instructions_key: nil])

      assert {:ok, resumed} =
               DataCollection.resume_participation(condition, %{
                 prolific_participant_id: participation.prolific_participant_id,
                 prolific_study_id: participation.prolific_study_id,
                 prolific_session_id: participation.prolific_session_id
               })

      assert resumed.instructions_key == "two-page-instructions.v1"
    end

    test "advances sequentially, rejects skips, and accepts acknowledged stale pages" do
      condition =
        condition_fixture(:comparison, %{instructions_key: "two-page-instructions.v1"})

      run_fixture(condition)
      assert {:ok, participation} = assign(condition)

      assert {:ok,
              %{
                instruction_set: SocialCrowdWork.TwoPageInstructionSet,
                page: SocialCrowdWork.TestInstructionPage,
                page_number: 1,
                total_pages: 2
              }} = DataCollection.instruction_page(participation)

      assert {:error, :instruction_page_out_of_order} =
               DataCollection.advance_instruction_page(participation, 2)

      assert {:ok, first_advance} =
               DataCollection.advance_instruction_page(participation, 1)

      assert first_advance.instruction_pages_completed == 1
      assert first_advance.instructions_completed_at == nil

      assert {:ok, stale_advance} =
               DataCollection.advance_instruction_page(participation, 1)

      assert stale_advance.instruction_pages_completed == 1

      assert {:ok,
              %{
                page: SocialCrowdWork.SecondTestInstructionPage,
                page_number: 2,
                total_pages: 2
              }} = DataCollection.instruction_page(participation)

      assert {:ok, completed_instructions} =
               DataCollection.advance_instruction_page(participation, 2)

      assert completed_instructions.instruction_pages_completed == 2
      assert completed_instructions.instructions_completed_at
      assert {:ok, :complete} = DataCollection.instruction_page(participation)

      assert {:ok, stale_after_completion} =
               DataCollection.advance_instruction_page(participation, 1)

      assert stale_after_completion.instruction_pages_completed == 2

      assert stale_after_completion.instructions_completed_at ==
               completed_instructions.instructions_completed_at

      events = Repo.all(ParticipantEvent)

      assert Enum.sort(Enum.map(events, & &1.kind)) ==
               [:instruction_page_advanced, :instructions_completed]

      assert Enum.any?(events, fn event ->
               event.metadata == %{
                 "instructions_key" => "two-page-instructions.v1",
                 "page_key" => "test-instructions-introduction.v1",
                 "page_number" => 1
               }
             end)
    end

    test "allows task flow without instructions and enforces required instructions" do
      condition_without_instructions = condition_fixture()
      run_without_instructions = run_fixture(condition_without_instructions)
      assert {:ok, participation_without_instructions} = assign(condition_without_instructions)
      [task_without_instructions] = run_without_instructions.tasks

      assert {:ok, :complete} =
               DataCollection.instruction_page(participation_without_instructions)

      assert {:error, :instruction_page_out_of_order} =
               DataCollection.advance_instruction_page(participation_without_instructions, 1)

      assert {:ok, _response} =
               DataCollection.record_response(
                 participation_without_instructions,
                 task_without_instructions.id,
                 "test-comparison.v1",
                 :skip
               )

      condition =
        condition_fixture(:comparison, %{instructions_key: "two-page-instructions.v1"})

      run = run_fixture(condition)
      assert {:ok, participation} = assign(condition)
      [task] = run.tasks

      assert {:error, :instructions_incomplete} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :skip
               )

      assert {:ok, _participation} =
               DataCollection.advance_instruction_page(participation, 1)

      assert {:error, :instructions_incomplete} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :skip
               )

      assert {:ok, _participation} =
               DataCollection.advance_instruction_page(participation, 2)

      assert {:ok, _response} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :skip
               )
    end

    test "returns an error for a retired instruction definition" do
      condition = condition_fixture()
      run_fixture(condition)
      assert {:ok, participation} = assign(condition)

      Participation
      |> where([stored], stored.id == ^participation.id)
      |> Repo.update_all(set: [instructions_key: "retired-instructions.v1"])

      assert {:error, :unknown_instruction_set} =
               DataCollection.instruction_page(participation)

      assert {:error, :unknown_instruction_set} =
               DataCollection.advance_instruction_page(participation, 1)
    end
  end

  describe "participant launch lifecycle" do
    test "creates unique DB-backed launches without creating participation and resolves them" do
      condition = condition_fixture()
      attrs = participation_attrs(condition)

      tokens = for _ <- 1..3, do: create_launch(condition, attrs)

      token_hashes =
        Enum.map(tokens, fn token -> elem(ParticipantLaunch.hash_token(token), 1) end)

      assert length(Enum.uniq(tokens)) == 3
      assert Repo.aggregate(ParticipantLaunch, :count) == 3
      assert Repo.aggregate(Participation, :count) == 0

      for {token, token_hash} <- Enum.zip(tokens, token_hashes) do
        assert {:ok, result} = DataCollection.resolve_participant_launch(token)
        assert result.condition.id == condition.id
        assert result.launch.token_hash == token_hash
        assert result.participation == nil
      end

      assert Enum.sort(Enum.map(Repo.all(ParticipantLaunch), & &1.token_hash)) ==
               Enum.sort(token_hashes)

      assert {:error, :invalid_launch} = DataCollection.resolve_participant_launch("malformed")
    end

    test "preattaches only an exact existing participation and uses post-consent TTL" do
      condition = condition_fixture()
      run_fixture(condition)
      attrs = participation_attrs(condition)

      assert {:ok, participation} =
               DataCollection.consent_and_assign_run(condition, attrs, condition.consent_key)

      token = create_launch(condition, attrs)

      assert {:ok, %{launch: launch, participation: attached}} =
               DataCollection.resolve_participant_launch(token)

      assert attached.id == participation.id

      assert DateTime.diff(launch.expires_at, launch.inserted_at) ==
               Application.fetch_env!(
                 :social_crowd_work,
                 :participant_launch_post_consent_ttl_seconds
               )

      other_condition = condition_fixture()

      assert {:error, :session_condition_mismatch} =
               DataCollection.create_participant_launch(other_condition, attrs)

      assert {:error, :prolific_identity_mismatch} =
               DataCollection.create_participant_launch(condition, %{
                 attrs
                 | prolific_participant_id: "different"
               })
    end

    test "consent atomically creates and attaches participation and extends expiry" do
      condition = condition_fixture()
      run_fixture(condition)
      attrs = participation_attrs(condition)
      token = create_launch(condition, attrs)

      assert {:ok, participation} =
               DataCollection.consent_and_assign_run(token, condition.consent_key)

      assert {:ok, %{launch: launch, participation: attached}} =
               DataCollection.resolve_participant_launch(token)

      assert attached.id == participation.id
      assert launch.participation_id == participation.id

      assert DateTime.diff(launch.expires_at, DateTime.utc_now()) >
               Application.fetch_env!(
                 :social_crowd_work,
                 :participant_launch_pre_consent_ttl_seconds
               )
    end

    test "duplicate launch tokens for one session converge on one participation" do
      condition = condition_fixture()
      run_fixture(condition)
      attrs = participation_attrs(condition)
      tokens = for _ <- 1..3, do: create_launch(condition, attrs)
      supervisor = start_supervised!(Task.Supervisor)
      parent = self()

      tasks =
        Enum.map(tokens, fn token ->
          Task.Supervisor.async_nolink(supervisor, fn ->
            send(parent, {:ready, self()})

            receive do
              :consent -> DataCollection.consent_and_assign_run(token, condition.consent_key)
            end
          end)
        end)

      pids =
        for _ <- tasks do
          assert_receive {:ready, pid}
          pid
        end

      Enum.each(pids, &send(&1, :consent))

      ids =
        Enum.map(tasks, fn task ->
          assert {:ok, participation} = Task.await(task)
          participation.id
        end)

      assert length(Enum.uniq(ids)) == 1
      assert Repo.aggregate(Participation, :count) == 1

      assert Repo.aggregate(
               from(launch in ParticipantLaunch,
                 where: not is_nil(launch.participation_id)
               ),
               :count
             ) == 3
    end

    test "expired launches are invalid and are lazily deleted on creation" do
      condition = condition_fixture()
      attrs = participation_attrs(condition)
      expired_token = create_launch(condition, attrs)
      {:ok, expired_hash} = ParticipantLaunch.hash_token(expired_token)
      past = DateTime.utc_now() |> DateTime.add(-120, :second) |> DateTime.truncate(:second)

      ParticipantLaunch
      |> where([launch], launch.token_hash == ^expired_hash)
      |> Repo.update_all(set: [inserted_at: DateTime.add(past, -1, :second), expires_at: past])

      assert {:error, :invalid_launch} = DataCollection.resolve_participant_launch(expired_token)

      assert {:error, :invalid_launch} =
               DataCollection.consent_and_assign_run(expired_token, condition.consent_key)

      _fresh_token = create_launch(condition, participation_attrs(condition))
      refute Repo.get_by(ParticipantLaunch, token_hash: expired_hash)
    end

    test "declines only valid unattached launches" do
      condition = condition_fixture()
      attrs = participation_attrs(condition)
      token = create_launch(condition, attrs)

      assert {:ok, %ParticipantLaunch{}} = DataCollection.decline_participant_launch(token)
      assert {:error, :invalid_launch} = DataCollection.decline_participant_launch(token)

      run_fixture(condition)
      attached_token = create_launch(condition, participation_attrs(condition))

      assert {:ok, _participation} =
               DataCollection.consent_and_assign_run(attached_token, condition.consent_key)

      assert {:error, :already_consented} =
               DataCollection.decline_participant_launch(attached_token)
    end

    test "completion requires the exact completed participation and cleans every launch" do
      condition = condition_fixture()
      run = run_fixture(condition)
      attrs = participation_attrs(condition)
      tokens = for _ <- 1..3, do: create_launch(condition, attrs)
      [first_token | _] = tokens

      assert {:ok, participation} =
               DataCollection.consent_and_assign_run(first_token, condition.consent_key)

      for token <- tl(tokens) do
        assert {:ok, resumed} =
                 DataCollection.consent_and_assign_run(token, condition.consent_key)

        assert resumed.id == participation.id
      end

      assert {:error, :participation_not_completed} =
               DataCollection.complete_participant_launch(first_token)

      [task] = run.tasks

      assert {:ok, _response} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :skip
               )

      assert {:ok, _completed} = DataCollection.complete_participation(participation)

      assert {:ok, result} = DataCollection.complete_participant_launch(first_token)
      assert result.condition.id == condition.id
      assert result.completion_code == condition.prolific_completion_code
      assert Repo.aggregate(ParticipantLaunch, :count) == 0

      for token <- tokens do
        assert {:error, :invalid_launch} = DataCollection.resolve_participant_launch(token)
      end
    end
  end

  describe "responses and progress" do
    test "response changesets require a nonblank question key" do
      attrs = %{
        participation_id: 1,
        task_id: 1,
        run_id: 1,
        question_key: " ",
        choice: :post_a,
        answered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      changeset = Response.changeset(%Response{}, attrs, :comparison)

      assert "can't be blank" in errors_on(changeset).question_key
    end

    test "task page returns ordered questionnaire questions, responses, and progress" do
      condition = condition_fixture()

      run =
        run_fixture(condition, %{
          tasks: [
            comparison_task(1)
            |> Map.put(:questionnaire_key, "psychosocial-comparisons.v1")
          ]
        })

      assert {:ok, participation} = assign(condition)
      [task] = run.tasks

      assert {:ok, page} = DataCollection.task_page(participation, 1)
      assert page.task.id == task.id
      assert page.questionnaire.key() == "psychosocial-comparisons.v1"
      assert page.total_tasks == 1
      refute page.complete?
      assert page.active_question_key == "low-mood.v1"

      assert Enum.map(page.questions, &{&1.number, &1.key, &1.module, &1.response}) ==
               SocialCrowdWork.Questionnaires.PsychosocialComparisonsV1.questions()
               |> Enum.with_index(1)
               |> Enum.map(fn {module, number} -> {number, module.key(), module, nil} end)

      assert {:ok, response} =
               DataCollection.record_response(participation, task.id, "low-mood.v1", :post_a)

      assert {:ok, updated_page} = DataCollection.task_page(participation, 1)
      assert updated_page.active_question_key == "hopelessness.v1"
      refute updated_page.complete?
      assert Enum.at(updated_page.questions, 0).response.id == response.id
    end

    test "records all questionnaire answers including explicit skips in task order" do
      condition = condition_fixture()
      run = run_fixture(condition, %{tasks: [comparison_task(1), comparison_task(2)]})
      assert {:ok, participation} = assign(condition)
      first_task = Enum.find(run.tasks, &(&1.position == 1))
      second_task = Enum.find(run.tasks, &(&1.position == 2))

      assert DataCollection.next_incomplete_task(participation).position == 1

      assert {:ok, first_response} =
               DataCollection.record_response(
                 participation,
                 first_task.id,
                 "test-comparison.v1",
                 :post_a
               )

      assert first_response.choice == :post_a
      assert DataCollection.next_incomplete_task(participation).position == 2

      assert {:ok, skipped_response} =
               DataCollection.record_response(
                 participation,
                 second_task.id,
                 "test-comparison.v1",
                 :skip
               )

      assert skipped_response.choice == :skip
      assert DataCollection.next_incomplete_task(participation) == nil
      assert Repo.get!(Participation, participation.id).status == :in_progress
    end

    test "transactionally validates questionnaire, question, and choice identities" do
      comparison_condition = condition_fixture(:comparison)
      comparison_run = run_fixture(comparison_condition)
      assert {:ok, comparison_participation} = assign(comparison_condition)
      [comparison_task] = comparison_run.tasks

      assert {:error, :question_not_in_questionnaire} =
               DataCollection.record_response(
                 comparison_participation,
                 comparison_task.id,
                 "test-binary-question.v1",
                 :post_a
               )

      assert {:error, :choice_not_allowed} =
               DataCollection.record_response(
                 comparison_participation,
                 comparison_task.id,
                 "test-comparison.v1",
                 :yes
               )

      SocialCrowdWork.Experiments.Task
      |> where([task], task.id == ^comparison_task.id)
      |> Repo.update_all(set: [questionnaire_key: "unknown.v1"])

      assert {:error, :unknown_questionnaire} =
               DataCollection.record_response(
                 comparison_participation,
                 comparison_task.id,
                 "test-comparison.v1",
                 :post_a
               )

      assert {:error, :unknown_questionnaire} =
               DataCollection.task_page(comparison_participation, comparison_task.position)

      binary_condition = condition_fixture(:binary_question)
      binary_run = run_fixture(binary_condition)
      assert {:ok, binary_participation} = assign(binary_condition)
      [binary_task] = binary_run.tasks

      assert {:ok, response} =
               DataCollection.record_response(
                 binary_participation,
                 binary_task.id,
                 "test-binary-question.v1",
                 :no
               )

      assert response.choice == :no
      assert Repo.aggregate(Response, :count) == 1
    end

    test "rejects tasks from another run" do
      condition = condition_fixture()
      assigned_run = run_fixture(condition)
      other_run = run_fixture(condition)
      assert {:ok, participation} = assign(condition)

      outside_task =
        if participation.run_id == assigned_run.id,
          do: hd(other_run.tasks),
          else: hd(assigned_run.tasks)

      assert {:error, :task_not_in_run} =
               DataCollection.record_response(
                 participation,
                 outside_task.id,
                 "test-comparison.v1",
                 :post_a
               )
    end

    test "the database also prevents cross-run responses" do
      condition = condition_fixture()
      first_run = run_fixture(condition)
      second_run = run_fixture(condition)
      assert {:ok, participation} = assign(condition)

      outside_task =
        if participation.run_id == first_run.id,
          do: hd(second_run.tasks),
          else: hd(first_run.tasks)

      attrs = %{
        participation_id: participation.id,
        task_id: outside_task.id,
        run_id: participation.run_id,
        question_key: "test-comparison.v1",
        choice: :post_a,
        answered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      assert {:error, changeset} =
               %Response{}
               |> Response.changeset(attrs, :comparison)
               |> Repo.insert()

      assert "does not exist" in errors_on(changeset).task_id
    end

    test "updates an existing response before completion without creating another row" do
      condition = condition_fixture()
      run = run_fixture(condition)
      assert {:ok, participation} = assign(condition)
      [task] = run.tasks

      assert {:ok, original} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :post_a
               )

      assert {:ok, updated} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :post_b
               )

      assert {:ok, same} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :post_b
               )

      assert updated.id == original.id
      assert updated.inserted_at == original.inserted_at
      assert updated.choice == :post_b
      assert same.id == updated.id
      assert Repo.aggregate(Response, :count) == 1
    end

    test "completion requires exact expected task and question identities and counts skips" do
      condition = condition_fixture()

      run =
        run_fixture(condition, %{
          tasks: [
            comparison_task()
            |> Map.put(:questionnaire_key, "psychosocial-comparisons.v1")
          ]
        })

      assert {:ok, participation} = assign(condition)
      [task] = run.tasks

      assert {:error, :tasks_remaining} = DataCollection.complete_participation(participation)

      question_keys =
        SocialCrowdWork.Questionnaires.PsychosocialComparisonsV1.questions()
        |> Enum.map(& &1.key())

      for question_key <- Enum.drop(question_keys, -1) do
        assert {:ok, _response} =
                 DataCollection.record_response(participation, task.id, question_key, :skip)
      end

      assert DataCollection.next_incomplete_task(participation).id == task.id
      assert {:error, :tasks_remaining} = DataCollection.complete_participation(participation)

      assert {:ok, _response} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 List.last(question_keys),
                 :skip
               )

      assert DataCollection.next_incomplete_task(participation) == nil
      assert {:ok, page} = DataCollection.task_page(participation, 1)
      assert page.complete?
      assert page.active_question_key == nil
      assert {:ok, completed} = DataCollection.complete_participation(participation)
      assert completed.status == :completed
      assert completed.completed_at
      assert {:ok, same_completed} = DataCollection.complete_participation(completed)
      assert same_completed.id == completed.id
      assert same_completed.completed_at == completed.completed_at

      assert {:error, :participation_completed} =
               DataCollection.record_response(completed, task.id, "worry.v1", :post_a)
    end

    test "unexpected response identities keep a task incomplete" do
      condition = condition_fixture()
      run = run_fixture(condition)
      assert {:ok, participation} = assign(condition)
      [task] = run.tasks

      attrs = %{
        participation_id: participation.id,
        task_id: task.id,
        run_id: participation.run_id,
        question_key: "unexpected.v1",
        choice: :skip,
        answered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      assert {:ok, _unexpected} =
               %Response{}
               |> Response.changeset(attrs, :comparison)
               |> Repo.insert()

      assert {:ok, _expected} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :skip
               )

      assert DataCollection.next_incomplete_task(participation).id == task.id
      assert {:ok, page} = DataCollection.task_page(participation, 1)
      refute page.complete?
      assert {:error, :tasks_remaining} = DataCollection.complete_participation(participation)
    end
  end

  defp assign(condition) do
    DataCollection.consent_and_assign_run(
      condition,
      participation_attrs(condition),
      "test-consent.v1"
    )
  end

  defp create_launch(condition, attrs) do
    assert {:ok, token} = DataCollection.create_participant_launch(condition, attrs)
    token
  end
end
