defmodule SocialCrowdWorkWeb.AdminSessionController do
  use SocialCrowdWorkWeb, :controller

  alias SocialCrowdWork.Admins
  alias SocialCrowdWorkWeb.AdminAuth

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"admin" => admin_params}, info) do
    %{"email" => email, "password" => password} = admin_params

    if admin = Admins.get_admin_by_email_and_password(email, password) do
      conn
      |> put_flash(:info, info)
      |> AdminAuth.log_in_admin(admin, admin_params)
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/admins/log-in")
    end
  end

  def update_password(conn, %{"admin" => admin_params} = params) do
    admin = conn.assigns.current_scope.admin
    true = Admins.sudo_mode?(admin)
    {:ok, {_admin, expired_tokens}} = Admins.update_admin_password(admin, admin_params)

    # disconnect all existing LiveViews with old sessions
    AdminAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:admin_return_to, ~p"/admins/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> AdminAuth.log_out_admin()
  end
end
