defmodule Mix.Tasks.SocialCrowdWork.ExportTest do
  use SocialCrowdWork.DataCase, async: false

  alias SocialCrowdWork.DataCollection

  import SocialCrowdWork.Fixtures

  test "writes filtered JSONL through the reusable exporter" do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous_shell) end)

    condition = condition_fixture()
    run_fixture(condition)

    assert {:ok, _participation} =
             DataCollection.consent_and_assign_run(
               condition,
               participation_attrs(condition),
               "test-consent.v1"
             )

    path =
      Path.join(
        System.tmp_dir!(),
        "social-crowd-work-export-#{System.unique_integer([:positive])}.jsonl"
      )

    on_exit(fn -> File.rm(path) end)

    Mix.Task.reenable("social_crowd_work.export")
    Mix.Tasks.SocialCrowdWork.Export.run(["--condition", condition.key, path])

    assert_receive {:mix_shell, :info, [message]}
    assert message =~ "Exported 1 task row(s)"

    assert [line] = path |> File.read!() |> String.split("\n", trim: true)
    record = Jason.decode!(line)
    assert record["schema_version"] == "2"
    assert record["condition"]["key"] == condition.key
    assert record["question"] == %{"key" => "test-comparison.v1", "number" => 1}
    assert record["response"] == nil
  end
end
