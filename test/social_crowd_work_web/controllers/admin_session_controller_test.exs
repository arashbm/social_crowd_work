defmodule SocialCrowdWorkWeb.AdminSessionControllerTest do
  use SocialCrowdWorkWeb.ConnCase, async: true

  import SocialCrowdWork.AdminsFixtures

  setup do
    %{admin: admin_fixture()}
  end

  describe "POST /admins/log-in - email and password" do
    test "logs the admin in", %{conn: conn, admin: admin} do
      admin = set_password(admin)

      conn =
        post(conn, ~p"/admins/log-in", %{
          "admin" => %{"email" => admin.email, "password" => valid_admin_password()}
        })

      assert get_session(conn, :admin_token)
      assert redirected_to(conn) == ~p"/admin"
    end

    test "logs the admin in with remember me", %{conn: conn, admin: admin} do
      admin = set_password(admin)

      conn =
        post(conn, ~p"/admins/log-in", %{
          "admin" => %{
            "email" => admin.email,
            "password" => valid_admin_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_social_crowd_work_web_admin_remember_me"]
      assert redirected_to(conn) == ~p"/admin"
    end

    test "logs the admin in with return to", %{conn: conn, admin: admin} do
      admin = set_password(admin)

      conn =
        conn
        |> init_test_session(admin_return_to: "/foo/bar")
        |> post(~p"/admins/log-in", %{
          "admin" => %{
            "email" => admin.email,
            "password" => valid_admin_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, admin: admin} do
      conn =
        post(conn, ~p"/admins/log-in?mode=password", %{
          "admin" => %{"email" => admin.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
      assert redirected_to(conn) == ~p"/admins/log-in"
    end
  end

  describe "DELETE /admins/log-out" do
    test "logs the admin out", %{conn: conn, admin: admin} do
      conn = conn |> log_in_admin(admin) |> delete(~p"/admins/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :admin_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the admin is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/admins/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :admin_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
