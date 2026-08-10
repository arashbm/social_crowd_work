defmodule SocialCrowdWork.AdminsTest do
  use SocialCrowdWork.DataCase

  alias SocialCrowdWork.Admins

  import SocialCrowdWork.AdminsFixtures
  alias SocialCrowdWork.Admins.{Admin, AdminToken}

  describe "get_admin_by_email/1" do
    test "does not return the admin if the email does not exist" do
      refute Admins.get_admin_by_email("unknown@example.com")
    end

    test "returns the admin if the email exists" do
      %{id: id} = admin = admin_fixture()
      assert %Admin{id: ^id} = Admins.get_admin_by_email(admin.email)
    end
  end

  describe "get_admin_by_email_and_password/2" do
    test "does not return the admin if the email does not exist" do
      refute Admins.get_admin_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the admin if the password is not valid" do
      admin = admin_fixture() |> set_password()
      refute Admins.get_admin_by_email_and_password(admin.email, "invalid")
    end

    test "returns the admin if the email and password are valid" do
      %{id: id} = admin = admin_fixture() |> set_password()

      assert %Admin{id: ^id} =
               Admins.get_admin_by_email_and_password(admin.email, valid_admin_password())
    end
  end

  describe "get_admin!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Admins.get_admin!(-1)
      end
    end

    test "returns the admin with the given id" do
      %{id: id} = admin = admin_fixture()
      assert %Admin{id: ^id} = Admins.get_admin!(admin.id)
    end
  end

  describe "register_admin/1" do
    test "requires email to be set" do
      {:error, changeset} = Admins.register_admin(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Admins.register_admin(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Admins.register_admin(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = admin_fixture()
      {:error, changeset} = Admins.register_admin(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Admins.register_admin(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers admins without password" do
      email = unique_admin_email()
      {:ok, admin} = Admins.register_admin(valid_admin_attributes(email: email))
      assert admin.email == email
      assert is_nil(admin.hashed_password)
      assert is_nil(admin.confirmed_at)
      assert is_nil(admin.password)
    end
  end

  describe "create_admin/1" do
    test "creates a confirmed admin with a password" do
      email = unique_admin_email()

      assert {:ok, admin} =
               Admins.create_admin(%{email: email, password: valid_admin_password()})

      assert admin.email == email
      assert admin.confirmed_at
      assert admin.hashed_password
      assert Admin.valid_password?(admin, valid_admin_password())
    end

    test "validates the password" do
      assert {:error, changeset} =
               Admins.create_admin(%{email: unique_admin_email(), password: "too short"})

      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Admins.sudo_mode?(%Admin{authenticated_at: DateTime.utc_now()})
      assert Admins.sudo_mode?(%Admin{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Admins.sudo_mode?(%Admin{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Admins.sudo_mode?(
               %Admin{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Admins.sudo_mode?(%Admin{})
    end
  end

  describe "change_admin_email/3" do
    test "returns a admin changeset" do
      assert %Ecto.Changeset{} = changeset = Admins.change_admin_email(%Admin{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_admin_update_email_instructions/3" do
    setup do
      %{admin: admin_fixture()}
    end

    test "sends token through notification", %{admin: admin} do
      token =
        extract_admin_token(fn url ->
          Admins.deliver_admin_update_email_instructions(admin, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert admin_token = Repo.get_by(AdminToken, token: :crypto.hash(:sha256, token))
      assert admin_token.admin_id == admin.id
      assert admin_token.sent_to == admin.email
      assert admin_token.context == "change:current@example.com"
    end
  end

  describe "update_admin_email/2" do
    setup do
      admin = unconfirmed_admin_fixture()
      email = unique_admin_email()

      token =
        extract_admin_token(fn url ->
          Admins.deliver_admin_update_email_instructions(
            %{admin | email: email},
            admin.email,
            url
          )
        end)

      %{admin: admin, token: token, email: email}
    end

    test "updates the email with a valid token", %{admin: admin, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Admins.update_admin_email(admin, token)
      changed_admin = Repo.get!(Admin, admin.id)
      assert changed_admin.email != admin.email
      assert changed_admin.email == email
      refute Repo.get_by(AdminToken, admin_id: admin.id)
    end

    test "does not update email with invalid token", %{admin: admin} do
      assert Admins.update_admin_email(admin, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(Admin, admin.id).email == admin.email
      assert Repo.get_by(AdminToken, admin_id: admin.id)
    end

    test "does not update email if admin email changed", %{admin: admin, token: token} do
      assert Admins.update_admin_email(%{admin | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Admin, admin.id).email == admin.email
      assert Repo.get_by(AdminToken, admin_id: admin.id)
    end

    test "does not update email if token expired", %{admin: admin, token: token} do
      {1, nil} = Repo.update_all(AdminToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Admins.update_admin_email(admin, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(Admin, admin.id).email == admin.email
      assert Repo.get_by(AdminToken, admin_id: admin.id)
    end
  end

  describe "change_admin_password/3" do
    test "returns a admin changeset" do
      assert %Ecto.Changeset{} = changeset = Admins.change_admin_password(%Admin{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Admins.change_admin_password(
          %Admin{},
          %{
            "password" => "new valid password"
          },
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_admin_password/2" do
    setup do
      %{admin: admin_fixture()}
    end

    test "validates password", %{admin: admin} do
      {:error, changeset} =
        Admins.update_admin_password(admin, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{admin: admin} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Admins.update_admin_password(admin, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{admin: admin} do
      {:ok, {admin, expired_tokens}} =
        Admins.update_admin_password(admin, %{
          password: "new valid password"
        })

      assert expired_tokens == []
      assert is_nil(admin.password)
      assert Admins.get_admin_by_email_and_password(admin.email, "new valid password")
    end

    test "deletes all tokens for the given admin", %{admin: admin} do
      _ = Admins.generate_admin_session_token(admin)

      {:ok, {_, _}} =
        Admins.update_admin_password(admin, %{
          password: "new valid password"
        })

      refute Repo.get_by(AdminToken, admin_id: admin.id)
    end
  end

  describe "generate_admin_session_token/1" do
    setup do
      %{admin: admin_fixture()}
    end

    test "generates a token", %{admin: admin} do
      token = Admins.generate_admin_session_token(admin)
      assert admin_token = Repo.get_by(AdminToken, token: token)
      assert admin_token.context == "session"
      assert admin_token.authenticated_at != nil

      # Creating the same token for another admin should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%AdminToken{
          token: admin_token.token,
          admin_id: admin_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given admin in new token", %{admin: admin} do
      admin = %{admin | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Admins.generate_admin_session_token(admin)
      assert admin_token = Repo.get_by(AdminToken, token: token)
      assert admin_token.authenticated_at == admin.authenticated_at
      assert DateTime.compare(admin_token.inserted_at, admin.authenticated_at) == :gt
    end
  end

  describe "get_admin_by_session_token/1" do
    setup do
      admin = admin_fixture()
      token = Admins.generate_admin_session_token(admin)
      %{admin: admin, token: token}
    end

    test "returns admin by token", %{admin: admin, token: token} do
      assert {session_admin, token_inserted_at} = Admins.get_admin_by_session_token(token)
      assert session_admin.id == admin.id
      assert session_admin.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return admin for invalid token" do
      refute Admins.get_admin_by_session_token("oops")
    end

    test "does not return admin for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(AdminToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Admins.get_admin_by_session_token(token)
    end
  end

  describe "get_admin_by_magic_link_token/1" do
    setup do
      admin = admin_fixture()
      {encoded_token, _hashed_token} = generate_admin_magic_link_token(admin)
      %{admin: admin, token: encoded_token}
    end

    test "returns admin by token", %{admin: admin, token: token} do
      assert session_admin = Admins.get_admin_by_magic_link_token(token)
      assert session_admin.id == admin.id
    end

    test "does not return admin for invalid token" do
      refute Admins.get_admin_by_magic_link_token("oops")
    end

    test "does not return admin for expired token", %{token: token} do
      {1, nil} = Repo.update_all(AdminToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Admins.get_admin_by_magic_link_token(token)
    end
  end

  describe "login_admin_by_magic_link/1" do
    test "confirms admin and expires tokens" do
      admin = unconfirmed_admin_fixture()
      refute admin.confirmed_at
      {encoded_token, hashed_token} = generate_admin_magic_link_token(admin)

      assert {:ok, {admin, [%{token: ^hashed_token}]}} =
               Admins.login_admin_by_magic_link(encoded_token)

      assert admin.confirmed_at
    end

    test "returns admin and (deleted) token for confirmed admin" do
      admin = admin_fixture()
      assert admin.confirmed_at
      {encoded_token, _hashed_token} = generate_admin_magic_link_token(admin)
      assert {:ok, {^admin, []}} = Admins.login_admin_by_magic_link(encoded_token)
      # one time use only
      assert {:error, :not_found} = Admins.login_admin_by_magic_link(encoded_token)
    end

    test "raises when unconfirmed admin has password set" do
      admin = unconfirmed_admin_fixture()
      {1, nil} = Repo.update_all(Admin, set: [hashed_password: "hashed"])
      {encoded_token, _hashed_token} = generate_admin_magic_link_token(admin)

      assert_raise RuntimeError, ~r/magic link log in is not allowed/, fn ->
        Admins.login_admin_by_magic_link(encoded_token)
      end
    end
  end

  describe "delete_admin_session_token/1" do
    test "deletes the token" do
      admin = admin_fixture()
      token = Admins.generate_admin_session_token(admin)
      assert Admins.delete_admin_session_token(token) == :ok
      refute Admins.get_admin_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{admin: unconfirmed_admin_fixture()}
    end

    test "sends token through notification", %{admin: admin} do
      token =
        extract_admin_token(fn url ->
          Admins.deliver_login_instructions(admin, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert admin_token = Repo.get_by(AdminToken, token: :crypto.hash(:sha256, token))
      assert admin_token.admin_id == admin.id
      assert admin_token.sent_to == admin.email
      assert admin_token.context == "login"
    end
  end

  describe "inspect/2 for the Admin module" do
    test "does not include password" do
      refute inspect(%Admin{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
