defmodule Mix.Tasks.SocialCrowdWork.ImportTest do
  use SocialCrowdWork.DataCase, async: false

  test "dry-runs a manifest through the reusable importer" do
    previous_shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous_shell) end)

    path =
      Path.join(
        System.tmp_dir!(),
        "social-crowd-work-import-#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    contents =
      Jason.encode!(%{
        "format_version" => "1",
        "conditions" => [
          %{
            "key" => "cli-test-condition",
            "task_type" => "comparison",
            "variants" => %{"phase" => "test"},
            "runs" => [
              %{
                "key" => "run-001",
                "tasks" => [
                  %{
                    "position" => 1,
                    "prompt_key" => "test-comparison.v1",
                    "stimuli" => %{
                      "post_a" => %{"text" => "First"},
                      "post_b" => %{"text" => "Second"}
                    }
                  }
                ]
              }
            ]
          }
        ]
      })

    File.write!(path, contents)
    Mix.Task.reenable("social_crowd_work.import")
    Mix.Tasks.SocialCrowdWork.Import.run(["--dry-run", path])

    assert_receive {:mix_shell, :info, [message]}
    assert message =~ "Manifest is valid"
    assert message =~ "1 condition(s), 1 run(s), 1 task(s)"
  end
end
