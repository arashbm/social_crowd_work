defmodule SocialCrowdWorkWeb.ParticipantLiveTest do
  use SocialCrowdWorkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialCrowdWork.Fixtures

  alias SocialCrowdWork.DataCollection.{Participation, Response}
  alias SocialCrowdWork.Repo

  test "requires a verified entry session", %{conn: conn} do
    assert {:ok, view, _html} = live(conn, ~p"/participate")
    assert has_element?(view, "#participation-error")
    refute has_element?(view, "#consent-panel")
  end

  test "renders versioned consent with visible shortcuts and persists nothing before acceptance",
       %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition)
    attrs = participation_attrs(condition)

    {:ok, view, _html} = enter_study(conn, condition, attrs)

    assert has_element?(view, "#test-consent-content")
    assert has_element?(view, "#accept-consent[data-shortcut='Enter,space']")
    refute has_element?(view, "#decline-consent[data-shortcut]")
    assert has_element?(view, "#participant-shortcuts[phx-hook]")
    assert has_element?(view, "#participant-theme-switch[aria-label='Color theme']")
    assert has_element?(view, "#theme-system[data-phx-theme='system']")
    assert has_element?(view, "#theme-light[data-phx-theme='light']")
    assert has_element?(view, "#theme-dark[data-phx-theme='dark']")
    assert Repo.aggregate(Participation, :count) == 0
  end

  test "renders the production privacy notice and consent statements", %{conn: conn} do
    condition =
      condition_fixture(:comparison, %{consent_key: "psychosocial-signals-consent.v1"})

    run_fixture(condition)
    attrs = participation_attrs(condition)

    {:ok, view, _html} = enter_study(conn, condition, attrs)

    assert has_element?(
             view,
             "#privacy-notice-document[src='/documents/research_study_privacy_notice.pdf']"
           )

    assert has_element?(view, "#consent-statements-heading")
    assert has_element?(view, "#psychosocial-signals-consent-v1", "I give my consent")
    assert Repo.aggregate(Participation, :count) == 0
  end

  test "accepts consent and displays comparison actions in fixed imported order", %{conn: conn} do
    condition = condition_fixture()

    run_fixture(condition, %{
      tasks: [
        %{
          position: 1,
          prompt_key: "test-comparison.v1",
          stimuli: %{
            "post_a" => %{"text" => "Imported first"},
            "post_b" => %{"text" => "Imported second"}
          }
        }
      ]
    })

    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()

    assert has_element?(view, "#task-panel")
    assert has_element?(view, "#test-comparison-prompt")
    assert has_element?(view, "#post-a", "Imported first")
    assert has_element?(view, "#post-b", "Imported second")

    assert has_element?(
             view,
             "#comparison-answer-options > #answer-post-a:first-child[data-shortcut='a']"
           )

    assert has_element?(
             view,
             "#comparison-answer-options > #answer-equal:nth-child(2)[data-shortcut='s']"
           )

    assert has_element?(
             view,
             "#comparison-answer-options > #answer-post-b:nth-child(3)[data-shortcut='d']"
           )

    assert has_element?(view, "#comparison-skip > #answer-skip[data-shortcut='x']")
    assert has_element?(view, "#previous-task[data-shortcut='z'][disabled]")

    participation = Repo.get_by!(Participation, prolific_session_id: attrs.prolific_session_id)
    assert participation.consent_key == "test-consent.v1"
  end

  test "supports back navigation and updates an earlier final answer before completion", %{
    conn: conn
  } do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [comparison_task(1), comparison_task(2)]})
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()
    view |> element("#answer-post-a") |> render_click()

    assert has_element?(view, "#task-progress", "2 / 2")
    assert has_element?(view, "#previous-task:not([disabled])")

    view |> element("#previous-task") |> render_click()
    assert has_element?(view, "#task-progress", "1 / 2")
    assert has_element?(view, "#answer-post-a[aria-pressed='true']")

    view |> element("#answer-post-b") |> render_click()
    assert has_element?(view, "#task-progress", "2 / 2")

    participation = Repo.get_by!(Participation, prolific_session_id: attrs.prolific_session_id)
    first_task = SocialCrowdWork.Experiments.get_task_by_position(participation.run_id, 1)
    response = Repo.get_by!(Response, participation_id: participation.id, task_id: first_task.id)
    assert response.choice == :post_b
    assert Repo.aggregate(Response, :count) == 1
  end

  test "renders binary shortcuts and redirects to Prolific after the final answer", %{conn: conn} do
    condition = condition_fixture(:binary_question)
    run_fixture(condition)
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()

    assert has_element?(view, "#single-post")
    assert has_element?(view, "#answer-yes[data-shortcut='a']")
    assert has_element?(view, "#answer-no[data-shortcut='s']")
    assert has_element?(view, "#binary-skip > #answer-skip[data-shortcut='x']")

    view |> element("#answer-yes") |> render_click()

    completion_url =
      "https://app.prolific.com/submissions/complete?cc=#{condition.prolific_completion_code}"

    assert_redirect(view, completion_url)
    participation = Repo.get_by!(Participation, prolific_session_id: attrs.prolific_session_id)
    assert participation.status == :completed
  end

  test "a completed participant revisit gets the keyboard-accessible Prolific fallback", %{
    conn: conn
  } do
    condition = condition_fixture(:binary_question)
    run_fixture(condition)
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()
    view |> element("#answer-skip") |> render_click()
    assert_redirect(view)

    {:ok, revisited, _html} = enter_study(conn, condition, attrs)
    assert has_element?(revisited, "#participation-completed")
    assert has_element?(revisited, "#complete-on-prolific[data-shortcut='Enter,space']")
  end

  test "shows an unavailable state without persisting accepted consent when no run exists", %{
    conn: conn
  } do
    condition = condition_fixture()
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()

    assert has_element?(view, "#participation-unavailable")
    assert has_element?(view, "#unavailable-return-to-prolific[data-shortcut='Enter,space']")
    assert Repo.aggregate(Participation, :count) == 0
  end

  test "ignores a stale keyboard answer event for a different displayed position", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [comparison_task(1), comparison_task(2)]})
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()
    render_click(view, "answer", %{"choice" => "post_a", "position" => "99"})

    assert has_element?(view, "#task-progress", "1 / 2")
    assert Repo.aggregate(Response, :count) == 0
  end

  defp enter_study(conn, condition, attrs) do
    conn =
      get(
        conn,
        ~p"/participate/#{condition.entry_token}?#{%{"PROLIFIC_PID" => attrs.prolific_participant_id, "STUDY_ID" => attrs.prolific_study_id, "SESSION_ID" => attrs.prolific_session_id}}"
      )

    assert redirected_to(conn) == ~p"/participate"
    live(recycle(conn), ~p"/participate")
  end
end
