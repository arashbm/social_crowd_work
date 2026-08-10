# SocialCrowdWork

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Deployment

Pushing to GitHub automatically builds and pushes a Docker image to GitHub container registry. You can then pull the image and run it on your server.

Fetch the latest image and run on production:

```bash
docker compose --env-file prod.env up -d --pull always
```

The docker compose file will automatically create a PostgreSQL database, run migrations, and provide an HTTP proxy. When the TLS certificate eventually expires, run the following command to load the new on:

```bash
docker compose exec proxy nginx -s reload
```

Add an admin user:
```bash
read -r -p "Admin email: " ADMIN_EMAIL
read -r -s -p "Admin password (12-72 characters): " ADMIN_PASSWORD
printf '\n'

docker compose --env-file prod.env exec -T \
  -e "ADMIN_EMAIL=${ADMIN_EMAIL}" \
  -e "ADMIN_PASSWORD=${ADMIN_PASSWORD}" \
  app /app/bin/social_crowd_work eval '
{:ok, _} = Application.ensure_all_started(:social_crowd_work)

case SocialCrowdWork.Admins.create_admin(%{
       email: System.fetch_env!("ADMIN_EMAIL"),
       password: System.fetch_env!("ADMIN_PASSWORD")
     }) do
  {:ok, admin} ->
    IO.puts("Created confirmed administrator #{admin.email}")

  {:error, changeset} ->
    IO.inspect(changeset.errors, label: "Could not create administrator")
    System.halt(1)
end
'

unset ADMIN_EMAIL ADMIN_PASSWORD
```
