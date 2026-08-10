defmodule SocialCrowdWorkWeb.AdminLive.LoginTest do
  use SocialCrowdWorkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialCrowdWork.AdminsFixtures

  test "renders password login without public registration or magic links", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admins/log-in")

    assert has_element?(view, "#login_form_password")
    assert has_element?(view, "#admin_email")
    assert has_element?(view, "#admin_password")
    refute has_element?(view, "#login_form_magic")
    refute has_element?(view, "a[href='/admins/register']")
  end

  test "redirects with valid password credentials", %{conn: conn} do
    admin = admin_fixture() |> set_password()
    {:ok, view, _html} = live(conn, ~p"/admins/log-in")

    form =
      form(view, "#login_form_password",
        admin: %{email: admin.email, password: valid_admin_password(), remember_me: true}
      )

    conn = submit_form(form, conn)
    assert redirected_to(conn) == ~p"/admin"
  end

  test "rejects invalid credentials without disclosing account existence", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admins/log-in")

    form =
      form(view, "#login_form_password",
        admin: %{email: "missing@example.com", password: "invalid password"}
      )

    render_submit(form, %{admin: %{remember_me: true}})
    conn = follow_trigger_action(form, conn)

    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    assert redirected_to(conn) == ~p"/admins/log-in"
  end
end
