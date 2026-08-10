defmodule SocialCrowdWork.DataCollectionTest do
  use SocialCrowdWork.DataCase, async: false

  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.DataCollection.{Participation, Response}
  alias SocialCrowdWork.Experiments.Condition

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

  describe "responses and progress" do
    test "records comparison answers and explicit skips in order" do
      condition = condition_fixture()
      run = run_fixture(condition, %{tasks: [comparison_task(1), comparison_task(2)]})
      assert {:ok, participation} = assign(condition)

      assert DataCollection.next_unanswered_task(participation).position == 1
      first_task = Enum.find(run.tasks, &(&1.position == 1))
      second_task = Enum.find(run.tasks, &(&1.position == 2))

      assert {:ok, first_response} =
               DataCollection.record_response(participation, first_task.id, :post_a)

      assert first_response.choice == :post_a
      assert DataCollection.next_unanswered_task(participation).position == 2

      assert {:ok, skipped_response} =
               DataCollection.record_response(participation, second_task.id, :skip)

      assert skipped_response.choice == :skip
      assert DataCollection.next_unanswered_task(participation) == nil
      assert Repo.get!(Participation, participation.id).status == :in_progress
    end

    test "validates choices according to the condition type" do
      comparison_condition = condition_fixture(:comparison)
      comparison_run = run_fixture(comparison_condition)
      assert {:ok, comparison_participation} = assign(comparison_condition)
      [comparison_task] = comparison_run.tasks

      assert {:error, comparison_changeset} =
               DataCollection.record_response(comparison_participation, comparison_task.id, :yes)

      assert "is invalid" in errors_on(comparison_changeset).choice

      binary_condition = condition_fixture(:binary_question)
      binary_run = run_fixture(binary_condition)
      assert {:ok, binary_participation} = assign(binary_condition)
      [binary_task] = binary_run.tasks

      assert {:error, binary_changeset} =
               DataCollection.record_response(binary_participation, binary_task.id, :equal)

      assert "is invalid" in errors_on(binary_changeset).choice

      assert {:ok, response} =
               DataCollection.record_response(binary_participation, binary_task.id, :no)

      assert response.choice == :no
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
               DataCollection.record_response(participation, outside_task.id, :post_a)
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

      assert {:ok, original} = DataCollection.record_response(participation, task.id, :post_a)
      assert {:ok, updated} = DataCollection.record_response(participation, task.id, :post_b)
      assert {:ok, same} = DataCollection.record_response(participation, task.id, :post_b)

      assert updated.id == original.id
      assert updated.inserted_at == original.inserted_at
      assert updated.choice == :post_b
      assert same.id == updated.id
      assert Repo.aggregate(Response, :count) == 1
    end

    test "only completes a participation after every task has a response" do
      condition = condition_fixture()
      run = run_fixture(condition, %{tasks: [comparison_task(1), comparison_task(2)]})
      assert {:ok, participation} = assign(condition)

      assert {:error, :tasks_remaining} = DataCollection.complete_participation(participation)

      for task <- run.tasks do
        assert {:ok, _response} = DataCollection.record_response(participation, task.id, :skip)
      end

      assert {:ok, completed} = DataCollection.complete_participation(participation)
      assert completed.status == :completed
      assert completed.completed_at
      assert {:ok, same_completed} = DataCollection.complete_participation(completed)
      assert same_completed.id == completed.id

      assert {:error, :participation_completed} =
               DataCollection.record_response(completed, hd(run.tasks).id, :post_a)
    end
  end

  defp assign(condition) do
    DataCollection.consent_and_assign_run(
      condition,
      participation_attrs(condition),
      "test-consent.v1"
    )
  end
end
