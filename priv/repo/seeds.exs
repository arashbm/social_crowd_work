if Mix.env() == :dev do
  alias SocialCrowdWork.{Experiments, Imports}

  manifest_path = Path.expand("dev_manifest.json", __DIR__)
  manifest = File.read!(manifest_path)

  {:ok, import_result} =
    Imports.import_manifest(manifest, filename: Path.basename(manifest_path))

  condition_configs = [
    {"dev-comparison-en", "dev-comparison-study"},
    {"dev-binary-en", "dev-binary-study"}
  ]

  conditions =
    Enum.map(condition_configs, fn {condition_key, prolific_study_id} ->
      condition = Experiments.get_condition_by_key(condition_key)

      {:ok, condition} =
        Experiments.configure_condition(condition, %{
          prolific_study_id: prolific_study_id,
          prolific_completion_code: "DEVCOMPLETE",
          consent_key: "dev-consent.v1",
          status: :active
        })

      condition
    end)

  base_url = System.get_env("DEV_BASE_URL", "http://localhost:4000")

  launch_url = fn condition ->
    query =
      URI.encode_query(%{
        "PROLIFIC_PID" => "dev-participant-#{Ecto.UUID.generate()}",
        "STUDY_ID" => condition.prolific_study_id,
        "SESSION_ID" => "dev-session-#{Ecto.UUID.generate()}"
      })

    "#{base_url}/participate/#{condition.entry_token}?#{query}"
  end

  [comparison_condition, binary_condition] = conditions

  IO.puts("""

  Development data ready (#{import_result.status}).

  Comparison study:
  #{launch_url.(comparison_condition)}

  Binary-question study:
  #{launch_url.(binary_condition)}

  Run this seed script again for fresh fake participant IDs. Each condition has
  five single-use runs; use `mix ecto.reset` after consuming the run pool.
  """)
else
  IO.puts("Development sample data is skipped outside MIX_ENV=dev.")
end
