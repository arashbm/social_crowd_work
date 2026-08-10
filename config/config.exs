# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :social_crowd_work, :scopes,
  admin: [
    default: true,
    module: SocialCrowdWork.Admins.Scope,
    assign_key: :current_scope,
    access_path: [:admin, :id],
    schema_key: :admin_id,
    schema_type: :id,
    schema_table: :admins,
    test_data_fixture: SocialCrowdWork.AdminsFixtures,
    test_setup_helper: :register_and_log_in_admin
  ]

config :social_crowd_work,
  ecto_repos: [SocialCrowdWork.Repo],
  generators: [timestamp_type: :utc_datetime],
  prolific_completion_url: "https://app.prolific.com/submissions/complete"

# Configure the endpoint
config :social_crowd_work, SocialCrowdWorkWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SocialCrowdWorkWeb.ErrorHTML, json: SocialCrowdWorkWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SocialCrowdWork.PubSub,
  live_view: [signing_salt: "Y/Gw3DPp"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :social_crowd_work, SocialCrowdWork.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  social_crowd_work: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  social_crowd_work: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, [
  "PROLIFIC_PID",
  "STUDY_ID",
  "SESSION_ID",
  "prolific_participant_id",
  "prolific_study_id",
  "prolific_session_id"
]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
