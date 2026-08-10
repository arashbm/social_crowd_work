defmodule Mix.Tasks.SocialCrowdWork.Admin.Create do
  use Mix.Task

  alias SocialCrowdWork.Admins

  @shortdoc "Creates a confirmed administrator account"

  @impl Mix.Task
  def run([email]) do
    Mix.Task.run("app.start")

    password =
      System.get_env("ADMIN_PASSWORD") ||
        Mix.raise("set ADMIN_PASSWORD to a password of at least 12 characters")

    case Admins.create_admin(%{email: email, password: password}) do
      {:ok, admin} ->
        Mix.shell().info("Created administrator #{admin.email}")

      {:error, changeset} ->
        Mix.raise("could not create administrator: #{inspect(changeset.errors)}")
    end
  end

  def run(_args) do
    Mix.raise(
      "usage: ADMIN_PASSWORD='a secure password' mix social_crowd_work.admin.create EMAIL"
    )
  end
end
