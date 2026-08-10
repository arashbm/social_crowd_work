defmodule Mix.Tasks.SocialCrowdWork.Import do
  use Mix.Task

  alias SocialCrowdWork.Imports

  @shortdoc "Validates and imports an experiment manifest"
  @switches [dry_run: :boolean]

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] or length(paths) != 1 do
      Mix.raise("usage: mix social_crowd_work.import [--dry-run] PATH")
    end

    Mix.Task.run("app.start")
    path = hd(paths)

    contents =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, reason} -> Mix.raise("could not read #{path}: #{:file.format_error(reason)}")
      end

    case Imports.import_manifest(contents,
           filename: Path.basename(path),
           dry_run: Keyword.get(opts, :dry_run, false)
         ) do
      {:ok, result} ->
        Mix.shell().info(summary(result))

      {:error, errors} ->
        Enum.each(errors, &Mix.shell().error("#{&1.path}: #{&1.message}"))
        Mix.raise("manifest import failed with #{length(errors)} error(s)")
    end
  end

  defp summary(result) do
    action =
      case result.status do
        :validated -> "Manifest is valid"
        :imported -> "Manifest imported"
        :already_imported -> "Manifest was already imported"
      end

    "#{action}: #{result.condition_count} condition(s), #{result.run_count} run(s), " <>
      "#{result.task_count} task(s)"
  end
end
