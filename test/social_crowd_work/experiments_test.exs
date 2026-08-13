defmodule SocialCrowdWork.ExperimentsTest do
  use SocialCrowdWork.DataCase, async: true

  alias SocialCrowdWork.Experiments
  alias SocialCrowdWork.Experiments.{Run, Task}

  import SocialCrowdWork.Fixtures

  describe "conditions" do
    test "creates a condition with a generated public entry token" do
      condition =
        condition_fixture(:comparison, %{variants: %{"language" => "de", "phase" => "pilot"}})

      assert condition.task_type == :comparison
      assert condition.variants == %{"language" => "de", "phase" => "pilot"}
      assert is_binary(condition.entry_token)
      assert byte_size(condition.entry_token) >= 32
    end

    test "requires complete, known operational configuration before activation" do
      {:ok, condition} =
        Experiments.create_condition(%{
          key: "inactive-condition-#{System.unique_integer([:positive])}",
          task_type: :comparison,
          variants: %{}
        })

      assert {:error, changeset} = Experiments.configure_condition(condition, %{status: :active})
      assert "can't be blank" in errors_on(changeset).prolific_study_id
      assert "can't be blank" in errors_on(changeset).prolific_completion_code
      assert "can't be blank" in errors_on(changeset).consent_key

      assert {:error, changeset} =
               Experiments.configure_condition(condition, %{
                 prolific_study_id: "study-1",
                 prolific_completion_code: "COMPLETE1",
                 consent_key: "unknown-consent.v1",
                 status: :active
               })

      assert "is not a known consent definition" in errors_on(changeset).consent_key

      assert {:ok, active_condition} =
               Experiments.configure_condition(condition, %{
                 prolific_study_id: "study-1",
                 prolific_completion_code: "COMPLETE1",
                 consent_key: "test-consent.v1",
                 status: :active
               })

      assert active_condition.status == :active
      assert active_condition.consent_key == "test-consent.v1"
    end
  end

  describe "create_run_with_tasks/2" do
    test "task changesets require a nonblank questionnaire key" do
      attrs = %{
        run_id: 1,
        position: 1,
        questionnaire_key: " ",
        stimuli: %{
          "post_a" => %{"text" => "First"},
          "post_b" => %{"text" => "Second"}
        }
      }

      changeset = Task.changeset(%Task{}, attrs, :comparison)

      assert "can't be blank" in errors_on(changeset).questionnaire_key
    end

    test "stores comparison posts without discarding arbitrary properties" do
      condition = condition_fixture()
      import_batch = import_batch_fixture()

      post_a = %{
        "text" => "A post",
        "uri" => "at://example/post/1",
        "author" => %{"handle" => "person.example"},
        "offline_score" => 0.75
      }

      attrs = %{
        import_batch_id: import_batch.id,
        external_key: "run-1",
        tasks: [
          %{
            position: 1,
            questionnaire_key: "test-comparison.v1",
            stimuli: %{
              "post_a" => post_a,
              "post_b" => %{"text" => "Another post", "custom" => [1, 2, 3]}
            }
          }
        ]
      }

      assert {:ok, run} = Experiments.create_run_with_tasks(condition, attrs)
      assert [task] = run.tasks
      assert task.stimuli["post_a"] == post_a
      assert task.stimuli["post_b"]["custom"] == [1, 2, 3]
    end

    test "accepts a binary question with one post" do
      condition = condition_fixture(:binary_question)
      run = run_fixture(condition)

      assert [task] = run.tasks
      assert task.stimuli == %{"post" => %{"text" => "The post"}}
    end

    test "requires the exact stimuli roles for the condition's task type" do
      condition = condition_fixture(:comparison)
      import_batch = import_batch_fixture()

      attrs = %{
        import_batch_id: import_batch.id,
        external_key: "invalid-shape",
        tasks: [
          %{
            position: 1,
            questionnaire_key: "test-comparison.v1",
            stimuli: %{"post" => %{"text" => "Wrong role"}}
          }
        ]
      }

      assert {:error, changeset} = Experiments.create_run_with_tasks(condition, attrs)
      assert "must contain exactly post_a and post_b" in errors_on(changeset).stimuli
      refute Repo.get_by(Run, external_key: "invalid-shape")
    end

    test "requires every post to have non-blank string text" do
      condition = condition_fixture(:comparison)

      invalid_posts = [
        {%{}, "post_a.text must be a string"},
        {%{"text" => 12}, "post_a.text must be a string"},
        {%{"text" => "  "}, "post_a.text must not be blank"}
      ]

      for {post, expected_error} <- invalid_posts do
        attrs = %{
          import_batch_id: import_batch_fixture().id,
          external_key: "invalid-post-#{System.unique_integer([:positive])}",
          tasks: [
            %{
              position: 1,
              questionnaire_key: "test-comparison.v1",
              stimuli: %{
                "post_a" => post,
                "post_b" => %{"text" => "Valid"}
              }
            }
          ]
        }

        assert {:error, changeset} = Experiments.create_run_with_tasks(condition, attrs)
        assert expected_error in errors_on(changeset).stimuli
      end
    end

    test "rolls back the entire run when task positions are duplicated" do
      condition = condition_fixture()
      import_batch = import_batch_fixture()

      attrs = %{
        import_batch_id: import_batch.id,
        external_key: "duplicate-positions",
        tasks: [comparison_task(1), comparison_task(1)]
      }

      assert {:error, changeset} = Experiments.create_run_with_tasks(condition, attrs)
      assert "has already been taken" in errors_on(changeset).position
      refute Repo.get_by(Run, external_key: "duplicate-positions")
      assert Repo.aggregate(Task, :count) == 0
    end

    test "does not create an empty run" do
      condition = condition_fixture()

      assert {:error, :tasks_required} =
               Experiments.create_run_with_tasks(condition, %{
                 import_batch_id: import_batch_fixture().id,
                 external_key: "empty",
                 tasks: []
               })
    end

    test "keeps run keys unique within a condition across import batches" do
      condition = condition_fixture()
      run_fixture(condition, %{external_key: "shared-run-key"})

      attrs = %{
        import_batch_id: import_batch_fixture().id,
        external_key: "shared-run-key",
        tasks: [comparison_task()]
      }

      assert {:error, changeset} = Experiments.create_run_with_tasks(condition, attrs)
      assert "has already been taken" in errors_on(changeset).external_key
    end

    test "returns tasks in presentation order" do
      condition = condition_fixture()

      run =
        run_fixture(condition, %{
          tasks: [comparison_task(2), comparison_task(1)]
        })

      assert Enum.map(Experiments.list_run_tasks(run.id), & &1.position) == [1, 2]
      assert Experiments.get_task_by_position(run.id, 2).position == 2
    end
  end
end
