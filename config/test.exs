import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :argon2_elixir, t_cost: 1, m_cost: 8

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :social_crowd_work, SocialCrowdWorkWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "rkFKckn5fzv+NYI5uNJ0qbuJ7l9/IechKs8skX6RtZyegn/o96Q35TBbxmdhqhQl",
  server: false

# In test we don't send emails
config :social_crowd_work, SocialCrowdWork.Mailer, adapter: Swoosh.Adapters.Test

config :social_crowd_work,
  max_manifest_upload_size: 1_000,
  prompt_modules: [
    SocialCrowdWork.TestComparisonPrompt,
    SocialCrowdWork.TestBinaryQuestionPrompt
  ],
  consent_modules: [SocialCrowdWork.TestConsent]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
