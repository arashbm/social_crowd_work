defmodule SocialCrowdWork.Admins do
  @moduledoc """
  The Admins context.
  """

  import Ecto.Query, warn: false
  alias SocialCrowdWork.Repo

  alias SocialCrowdWork.Admins.{Admin, AdminToken, AdminNotifier}

  ## Database getters

  @doc """
  Gets a admin by email.

  ## Examples

      iex> get_admin_by_email("foo@example.com")
      %Admin{}

      iex> get_admin_by_email("unknown@example.com")
      nil

  """
  def get_admin_by_email(email) when is_binary(email) do
    Repo.get_by(Admin, email: email)
  end

  @doc """
  Gets a admin by email and password.

  ## Examples

      iex> get_admin_by_email_and_password("foo@example.com", "correct_password")
      %Admin{}

      iex> get_admin_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_admin_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    admin = Repo.get_by(Admin, email: email)
    if Admin.valid_password?(admin, password), do: admin
  end

  @doc """
  Gets a single admin.

  Raises `Ecto.NoResultsError` if the Admin does not exist.

  ## Examples

      iex> get_admin!(123)
      %Admin{}

      iex> get_admin!(456)
      ** (Ecto.NoResultsError)

  """
  def get_admin!(id), do: Repo.get!(Admin, id)

  ## Admin registration

  @doc """
  Registers a admin.

  ## Examples

      iex> register_admin(%{field: value})
      {:ok, %Admin{}}

      iex> register_admin(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_admin(attrs) do
    %Admin{}
    |> Admin.email_changeset(attrs)
    |> Repo.insert()
  end

  def create_admin(attrs) do
    %Admin{}
    |> Admin.email_changeset(attrs)
    |> Admin.password_changeset(attrs)
    |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now(:second))
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the admin is in sudo mode.

  The admin is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(admin, minutes \\ -20)

  def sudo_mode?(%Admin{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_admin, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the admin email.

  See `SocialCrowdWork.Admins.Admin.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_admin_email(admin)
      %Ecto.Changeset{data: %Admin{}}

  """
  def change_admin_email(admin, attrs \\ %{}, opts \\ []) do
    Admin.email_changeset(admin, attrs, opts)
  end

  @doc """
  Updates the admin email using the given token.

  If the token matches, the admin email is updated and the token is deleted.
  """
  def update_admin_email(admin, token) do
    context = "change:#{admin.email}"

    Repo.transact(fn ->
      with {:ok, query} <- AdminToken.verify_change_email_token_query(token, context),
           %AdminToken{sent_to: email} <- Repo.one(query),
           {:ok, admin} <- Repo.update(Admin.email_changeset(admin, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(AdminToken, where: [admin_id: ^admin.id, context: ^context])) do
        {:ok, admin}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the admin password.

  See `SocialCrowdWork.Admins.Admin.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_admin_password(admin)
      %Ecto.Changeset{data: %Admin{}}

  """
  def change_admin_password(admin, attrs \\ %{}, opts \\ []) do
    Admin.password_changeset(admin, attrs, opts)
  end

  @doc """
  Updates the admin password.

  Returns a tuple with the updated admin, as well as a list of expired tokens.

  ## Examples

      iex> update_admin_password(admin, %{password: ...})
      {:ok, {%Admin{}, [...]}}

      iex> update_admin_password(admin, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_admin_password(admin, attrs) do
    admin
    |> Admin.password_changeset(attrs)
    |> update_admin_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_admin_session_token(admin) do
    {token, admin_token} = AdminToken.build_session_token(admin)
    Repo.insert!(admin_token)
    token
  end

  @doc """
  Gets the admin with the given signed token.

  If the token is valid `{admin, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_admin_by_session_token(token) do
    {:ok, query} = AdminToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the admin with the given magic link token.
  """
  def get_admin_by_magic_link_token(token) do
    with {:ok, query} <- AdminToken.verify_magic_link_token_query(token),
         {admin, _token} <- Repo.one(query) do
      admin
    else
      _ -> nil
    end
  end

  @doc """
  Logs the admin in by magic link.

  There are three cases to consider:

  1. The admin has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The admin has not confirmed their email and no password is set.
     In this case, the admin gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The admin has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_admin_by_magic_link(token) do
    {:ok, query} = AdminToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%Admin{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%Admin{confirmed_at: nil} = admin, _token} ->
        admin
        |> Admin.confirm_changeset()
        |> update_admin_and_delete_all_tokens()

      {admin, token} ->
        Repo.delete!(token)
        {:ok, {admin, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given admin.

  ## Examples

      iex> deliver_admin_update_email_instructions(admin, current_email, &url(~p"/admins/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_admin_update_email_instructions(
        %Admin{} = admin,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, admin_token} = AdminToken.build_email_token(admin, "change:#{current_email}")

    Repo.insert!(admin_token)
    AdminNotifier.deliver_update_email_instructions(admin, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given admin.
  """
  def deliver_login_instructions(%Admin{} = admin, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, admin_token} = AdminToken.build_email_token(admin, "login")
    Repo.insert!(admin_token)
    AdminNotifier.deliver_login_instructions(admin, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_admin_session_token(token) do
    Repo.delete_all(from(AdminToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_admin_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, admin} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(AdminToken, admin_id: admin.id)

        Repo.delete_all(
          from(t in AdminToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id))
        )

        {:ok, {admin, tokens_to_expire}}
      end
    end)
  end
end
