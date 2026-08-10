# Development Data

Development uses placeholder prompt and consent modules from `dev/support/`. They are registered only in `config/dev.exs` and are not compiled into production or test releases.

The seed script imports `priv/repo/dev_manifest.json` through the same `SocialCrowdWork.Imports` service used by the CLI and future admin UI. It creates:

- One English development comparison condition
- One English development binary-question condition
- Five single-use runs per condition
- Three tasks per run
- Nested metadata, multiline text, and HTML-like text for rendering checks

Create or refresh a clean development database with:

```sh
mix ecto.reset
```

For an existing seeded database, print launch links with fresh fake Prolific participant and session IDs:

```sh
mix run priv/repo/seeds.exs
```

The manifest import is idempotent, so rerunning the seed script does not duplicate runs. Once all five runs for a condition have been assigned, use `mix ecto.reset` to restore the pool.

The generated links assume the application is running at `http://localhost:4000`. Override this when needed:

```sh
DEV_BASE_URL=http://localhost:4100 mix run priv/repo/seeds.exs
```

Development completion redirects to `/dev/prolific-complete` instead of leaving the application for Prolific. Production continues to use Prolific's official completion endpoint.
