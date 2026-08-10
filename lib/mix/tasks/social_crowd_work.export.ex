defmodule Mix.Tasks.SocialCrowdWork.Export do
  use Mix.Task

  alias SocialCrowdWork.Exports

  @shortdoc "Exports assigned tasks and responses as JSONL"
  @switches [condition: :string]

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} = OptionParser.parse(args, strict: @switches)

    if invalid != [] or length(paths) != 1 do
      Mix.raise("usage: mix social_crowd_work.export [--condition KEY] PATH")
    end

    Mix.Task.run("app.start")
    path = hd(paths)

    case File.open(path, [:write, :binary]) do
      {:ok, io_device} -> export(io_device, path, opts)
      {:error, reason} -> Mix.raise("could not open #{path}: #{:file.format_error(reason)}")
    end
  end

  defp export(io_device, path, opts) do
    result =
      try do
        Exports.reduce_jsonl(
          0,
          fn line, count ->
            :ok = IO.binwrite(io_device, line)
            count + 1
          end,
          condition_key: Keyword.get(opts, :condition)
        )
      after
        File.close(io_device)
      end

    case result do
      {:ok, count} -> Mix.shell().info("Exported #{count} task row(s) to #{path}")
      {:error, reason} -> Mix.raise("export failed: #{inspect(reason)}")
    end
  end
end
