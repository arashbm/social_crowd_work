defmodule SocialCrowdWork.ImportsTest do
  use SocialCrowdWork.DataCase, async: true

  alias SocialCrowdWork.Experiments.{Condition, ImportBatch, Run, Task}
  alias SocialCrowdWork.Imports

  import SocialCrowdWork.Fixtures

  describe "import_manifest/2" do
    test "imports conditions, exact runs, tasks, and arbitrary post properties" do
      key = unique_key("comparison")

      post_a = %{
        "text" => "First post",
        "uri" => "at://example/post/1",
        "author" => %{"handle" => "person.example"},
        "custom_score" => 0.8
      }

      contents =
        encode_manifest([
          condition_data(key, [run_data("run-001", [comparison_task_data(1, post_a)])])
        ])

      assert {:ok, result} =
               Imports.import_manifest(contents, filename: "/untrusted/path/pilot.json")

      assert result.status == :imported
      assert result.condition_count == 1
      assert result.run_count == 1
      assert result.task_count == 1
      assert result.import_batch.original_filename == "pilot.json"
      assert byte_size(result.import_batch.source_sha256) == 64

      condition = Repo.get_by!(Condition, key: key)
      assert condition.status == :draft
      assert condition.task_type == :comparison
      assert condition.variants == %{"language" => "en", "phase" => "pilot"}

      run = Repo.get_by!(Run, condition_id: condition.id, external_key: "run-001")
      task = Repo.get_by!(Task, run_id: run.id, position: 1)
      assert task.questionnaire_key == "test-comparison.v1"
      assert task.stimuli["post_a"] == post_a
    end

    test "treats an exact repeated file as an idempotent import" do
      contents = valid_manifest(unique_key("idempotent"))

      assert {:ok, imported} = Imports.import_manifest(contents, filename: "first.json")
      assert {:ok, repeated} = Imports.import_manifest(contents, filename: "renamed.json")

      assert imported.status == :imported
      assert repeated.status == :already_imported
      assert repeated.import_batch.id == imported.import_batch.id
      assert Repo.aggregate(ImportBatch, :count) == 1
      assert Repo.aggregate(Run, :count) == 1
    end

    test "validates a dry run without writing any records" do
      contents = valid_manifest(unique_key("dry-run"))

      assert {:ok, result} =
               Imports.import_manifest(contents, filename: "dry-run.json", dry_run: true)

      assert result.status == :validated
      assert result.import_batch == nil
      assert result.condition_count == 1
      assert result.run_count == 1
      assert result.task_count == 1
      assert Repo.aggregate(Condition, :count) == 0
      assert Repo.aggregate(ImportBatch, :count) == 0
    end

    test "allows later files to append new run keys to a matching condition" do
      key = unique_key("append")
      first = encode_manifest([condition_data(key, [run_data("run-001")])])
      second = encode_manifest([condition_data(key, [run_data("run-002")])])

      assert {:ok, _first_result} = Imports.import_manifest(first, filename: "first.json")
      assert {:ok, second_result} = Imports.import_manifest(second, filename: "second.json")

      assert second_result.status == :imported
      condition = Repo.get_by!(Condition, key: key)

      assert Run
             |> where([run], run.condition_id == ^condition.id)
             |> order_by([run], asc: run.external_key)
             |> select([run], run.external_key)
             |> Repo.all() == ["run-001", "run-002"]
    end

    test "a reformatted file cannot recreate an existing condition run key" do
      key = unique_key("reformatted")
      contents = valid_manifest(key)
      reformatted = contents |> Jason.decode!() |> Jason.encode!(pretty: true)

      assert contents != reformatted
      assert {:ok, _result} = Imports.import_manifest(contents, filename: "compact.json")

      assert {:error, errors} =
               Imports.import_manifest(reformatted, filename: "pretty.json")

      assert_error(errors, "conditions[0].runs[0].key", "already exists for this condition")
      assert Repo.aggregate(ImportBatch, :count) == 1
      assert Repo.aggregate(Run, :count) == 1
    end

    test "requires an existing condition's type and variants to match" do
      key = unique_key("mismatch")

      condition_fixture(:comparison, %{
        key: key,
        variants: %{"language" => "de", "phase" => "pilot"}
      })

      contents = encode_manifest([condition_data(key, [run_data("run-001")])])

      assert {:error, errors} = Imports.import_manifest(contents, filename: "mismatch.json")
      assert_error(errors, "conditions[0].variants", "do not match the existing condition")
      assert Repo.aggregate(ImportBatch, :count) == 0
    end

    test "does not write earlier valid conditions when a later condition conflicts" do
      existing_key = unique_key("existing")
      new_key = unique_key("new")
      existing_condition = condition_fixture(:comparison, %{key: existing_key})
      run_fixture(existing_condition, %{external_key: "run-001"})

      contents =
        encode_manifest([
          condition_data(new_key, [run_data("new-run")]),
          condition_data(existing_key, [run_data("run-001")])
        ])

      assert {:error, errors} = Imports.import_manifest(contents, filename: "atomic.json")
      assert_error(errors, "conditions[1].runs[0].key", "already exists for this condition")
      refute Repo.get_by(Condition, key: new_key)
      assert Repo.aggregate(ImportBatch, :count) == 1
    end
  end

  describe "manifest validation" do
    test "reports malformed JSON at the document root" do
      assert {:error, [error]} = Imports.validate_manifest("{not json")
      assert error.path == "$"
      assert error.message =~ "contains invalid JSON"
    end

    test "reports unknown questionnaires and incompatible task types at exact paths" do
      key = unique_key("questionnaires")

      unknown_questionnaire =
        comparison_task_data(1)
        |> Map.put("questionnaire_key", "does-not-exist.v1")

      incompatible_questionnaire =
        comparison_task_data(2)
        |> Map.put("questionnaire_key", "test-binary-question.v1")

      contents =
        encode_manifest([
          condition_data(key, [
            run_data("run-001", [unknown_questionnaire, incompatible_questionnaire])
          ])
        ])

      assert {:error, errors} = Imports.validate_manifest(contents)

      assert_error(
        errors,
        "conditions[0].runs[0].tasks[0].questionnaire_key",
        "is not a known questionnaire"
      )

      assert_error(
        errors,
        "conditions[0].runs[0].tasks[1].questionnaire_key",
        "is not compatible with comparison"
      )
    end

    test "reports invalid post text at its full stimuli path" do
      task = comparison_task_data(1, %{"text" => " "})

      contents =
        encode_manifest([condition_data(unique_key("text"), [run_data("run-001", [task])])])

      assert {:error, errors} = Imports.validate_manifest(contents)

      assert_error(
        errors,
        "conditions[0].runs[0].tasks[0].stimuli.post_a.text",
        "must not be blank"
      )
    end

    test "reports duplicate condition keys, run keys, and task positions" do
      key = unique_key("duplicates")

      duplicated_run =
        run_data("same-run", [comparison_task_data(1), comparison_task_data(1)])

      condition = condition_data(key, [duplicated_run, run_data("same-run")])
      contents = encode_manifest([condition, condition])

      assert {:error, errors} = Imports.validate_manifest(contents)
      assert_error(errors, "conditions[1].key", "is duplicated in this manifest")
      assert_error(errors, "conditions[0].runs[1].key", "is duplicated in this manifest")

      assert_error(
        errors,
        "conditions[0].runs[0].tasks[1].position",
        "is duplicated in this manifest"
      )
    end

    test "rejects unknown structural keys while allowing arbitrary post keys" do
      task =
        comparison_task_data(1, %{"text" => "Valid", "anything" => %{"nested" => true}})
        |> Map.put("typo", true)

      contents =
        encode_manifest([condition_data(unique_key("unknown"), [run_data("run-001", [task])])])

      assert {:error, errors} = Imports.validate_manifest(contents)
      assert_error(errors, "conditions[0].runs[0].tasks[0].typo", "is not allowed")

      refute Enum.any?(errors, &String.contains?(&1.path, "anything"))
    end

    test "accepts binary-question manifests with their own prompt and stimuli shape" do
      condition =
        condition_data(unique_key("binary"), [
          run_data("run-001", [
            %{
              "position" => 1,
              "questionnaire_key" => "test-binary-question.v1",
              "stimuli" => %{"post" => %{"text" => "A binary task post", "extra" => 1}}
            }
          ])
        ])
        |> Map.put("task_type", "binary_question")

      assert {:ok, plan} = Imports.validate_manifest(encode_manifest([condition]))
      assert hd(plan.conditions).task_type == :binary_question
    end

    test "requires task positions to be contiguous from one" do
      tasks = [comparison_task_data(1), comparison_task_data(3)]

      contents =
        encode_manifest([
          condition_data(unique_key("positions"), [run_data("run-001", tasks)])
        ])

      assert {:error, errors} = Imports.validate_manifest(contents)

      assert_error(
        errors,
        "conditions[0].runs[0].tasks[1].position",
        "must be 2"
      )
    end
  end

  defp valid_manifest(condition_key) do
    encode_manifest([condition_data(condition_key, [run_data("run-001")])])
  end

  defp encode_manifest(conditions) do
    Jason.encode!(%{"format_version" => "2", "conditions" => conditions})
  end

  defp condition_data(key, runs) do
    %{
      "key" => key,
      "task_type" => "comparison",
      "variants" => %{"language" => "en", "phase" => "pilot"},
      "runs" => runs
    }
  end

  defp run_data(key, tasks \\ [comparison_task_data(1)]) do
    %{"key" => key, "tasks" => tasks}
  end

  defp comparison_task_data(position, post_a \\ %{"text" => "First post"}) do
    %{
      "position" => position,
      "questionnaire_key" => "test-comparison.v1",
      "stimuli" => %{
        "post_a" => post_a,
        "post_b" => %{"text" => "Second post"}
      }
    }
  end

  defp unique_key(prefix) do
    "#{prefix}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp assert_error(errors, path, message) do
    assert Enum.any?(errors, &(&1.path == path and &1.message == message)),
           "expected #{path}: #{message}, got: #{inspect(errors)}"
  end
end
