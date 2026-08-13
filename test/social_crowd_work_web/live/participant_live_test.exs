defmodule SocialCrowdWorkWeb.ParticipantLiveTest do
  use SocialCrowdWorkWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialCrowdWork.Fixtures

  alias SocialCrowdWork.DataCollection.{ParticipantLaunch, Participation, Response}
  alias SocialCrowdWork.Repo

  test "rejects an invalid launch token without relying on session state", %{conn: conn} do
    launch_token = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
    assert {:ok, view, _html} = live(conn, ~p"/participate/#{launch_token}")
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
    assert has_element?(view, "#decline-consent[data-method='delete']")
    assert Repo.aggregate(Participation, :count) == 0
    assert Repo.aggregate(ParticipantLaunch, :count) == 1
  end

  test "refreshes the same launch before consent without creating participation", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition)
    attrs = participation_attrs(condition)
    {_entry_conn, participant_path} = launch_study(conn, condition, attrs)

    assert {:ok, first, _html} = live(recycle(conn), participant_path)
    assert has_element?(first, "#consent-panel")

    assert {:ok, refreshed, _html} = live(recycle(conn), participant_path)
    assert has_element?(refreshed, "#consent-panel")
    assert Repo.aggregate(Participation, :count) == 0
    assert Repo.aggregate(ParticipantLaunch, :count) == 1
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

  test "keeps two studies independent in one browser after both have launched", %{conn: conn} do
    first_condition = condition_fixture()
    second_condition = condition_fixture()
    run_fixture(first_condition)
    run_fixture(second_condition)

    first_attrs = participation_attrs(first_condition)

    second_attrs =
      participation_attrs(second_condition, %{
        prolific_participant_id: first_attrs.prolific_participant_id
      })

    {first_conn, first_path} = launch_study(conn, first_condition, first_attrs)

    {second_conn, second_path} =
      launch_study(recycle(first_conn), second_condition, second_attrs)

    {:ok, first_view, _html} = live(recycle(second_conn), first_path)
    {:ok, second_view, _html} = live(recycle(second_conn), second_path)

    assert has_element?(first_view, "#consent-panel")
    assert has_element?(second_view, "#consent-panel")

    first_view |> element("#accept-consent") |> render_click()
    second_view |> element("#accept-consent") |> render_click()

    first = Repo.get_by!(Participation, prolific_session_id: first_attrs.prolific_session_id)
    second = Repo.get_by!(Participation, prolific_session_id: second_attrs.prolific_session_id)

    assert first.id != second.id
    assert first.run_id != second.run_id
    assert first.prolific_participant_id == second.prolific_participant_id
  end

  test "renders posts once and the ordered questionnaire with only the first question active", %{
    conn: conn
  } do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [psychosocial_task(1, "Imported first", "Imported second")]})

    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()

    assert has_element?(view, "#task-panel")
    assert has_element?(view, "#post-a", "Imported first")
    assert has_element?(view, "#post-b", "Imported second")
    assert render(element(view, "#comparison-posts > #post-a"))
    assert render(element(view, "#comparison-posts > #post-b"))
    assert has_element?(view, "#question-1[data-question-key='worry.v1'][data-state='active']")

    assert has_element?(
             view,
             "#question-2[data-question-key='restlessness.v1'][data-state='locked']"
           )

    assert has_element?(
             view,
             "#question-3[data-question-key='cognitive-disruption.v1'][data-state='locked']"
           )

    assert has_element?(view, "#question-1-header[aria-expanded='true'][disabled]")
    assert has_element?(view, "#question-2-header[aria-expanded='false'][disabled]")

    assert has_element?(
             view,
             "#question-1-region[role='region'][aria-labelledby='question-1-header']"
           )

    assert has_element?(view, "#question-1-region #worry-prompt-v1")
    refute has_element?(view, "#question-2-region #restlessness-prompt-v1")

    assert has_element?(view, "#question-1-region #answer-post-a[data-shortcut='a']")
    assert has_element?(view, "#question-1-region #answer-equal[data-shortcut='s']")
    assert has_element?(view, "#question-1-region #answer-post-b[data-shortcut='d']")
    assert has_element?(view, "#comparison-skip > #answer-skip[data-shortcut='x']")
    assert has_element?(view, "#previous-task[data-shortcut='z'][disabled]")

    participation = Repo.get_by!(Participation, prolific_session_id: attrs.prolific_session_id)
    assert participation.consent_key == "test-consent.v1"
  end

  test "answers in order, locks future questions, and edits an answered question", %{
    conn: conn
  } do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [psychosocial_task()]})
    attrs = participation_attrs(condition)
    {_entry_conn, participant_path} = launch_study(conn, condition, attrs)
    {:ok, view, _html} = live(recycle(conn), participant_path)

    view |> element("#accept-consent") |> render_click()
    render_click(view, "open_question", %{"position" => "1", "question_key" => "restlessness.v1"})
    assert has_element?(view, "#question-2[data-state='locked']")

    view |> element("#answer-post-a") |> render_click()
    assert has_element?(view, "#question-1[data-state='answered']")

    assert has_element?(
             view,
             "#question-1-header[aria-expanded='false']:not([disabled])",
             "Post A"
           )

    assert has_element?(view, "#question-2[data-state='active']")
    assert has_element?(view, "#question-2-region #restlessness-prompt-v1")
    assert has_element?(view, "#question-3-header[disabled]")

    view |> element("#question-1-header") |> render_click()
    assert has_element?(view, "#question-1[data-state='active']")
    assert has_element?(view, "#answer-post-a[aria-pressed='true']")
    view |> element("#answer-post-b") |> render_click()
    assert has_element?(view, "#question-2[data-state='active']")

    participation = Repo.get_by!(Participation, prolific_session_id: attrs.prolific_session_id)
    first_task = SocialCrowdWork.Experiments.get_task_by_position(participation.run_id, 1)

    response =
      Repo.get_by!(Response,
        participation_id: participation.id,
        task_id: first_task.id,
        question_key: "worry.v1"
      )

    assert response.choice == :post_b
    assert Repo.aggregate(Response, :count) == 1
  end

  test "resumes a partial questionnaire at its first unanswered question", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [psychosocial_task()]})
    attrs = participation_attrs(condition)
    {_entry_conn, participant_path} = launch_study(conn, condition, attrs)
    {:ok, view, _html} = live(recycle(conn), participant_path)

    view |> element("#accept-consent") |> render_click()
    view |> element("#answer-post-a") |> render_click()

    {:ok, resumed, _html} = live(recycle(conn), participant_path)
    assert has_element?(resumed, "#question-1[data-state='answered']", "Post A")
    assert has_element?(resumed, "#question-2[data-state='active']")
    assert has_element?(resumed, "#question-3[data-state='locked']")
  end

  test "finishing a questionnaire advances to the next pair and previous reopens question one", %{
    conn: conn
  } do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [psychosocial_task(1), psychosocial_task(2)]})
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()
    answer_three_questions(view)

    assert_push_event(view, "scroll_to_top", %{})
    assert has_element?(view, "#task-progress", "2 / 2")
    view |> element("#previous-task") |> render_click()
    assert has_element?(view, "#task-progress", "1 / 2")
    assert has_element?(view, "#question-1[data-state='active']")
    assert has_element?(view, "#answer-post-a[aria-pressed='true']")
  end

  test "the last questionnaire answer completes and redirects", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [psychosocial_task()]})
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)

    view |> element("#accept-consent") |> render_click()
    answer_three_questions(view)

    assert {completion_path, %{}} = assert_redirect(view)
    assert completion_path =~ ~r|^/participate/[A-Za-z0-9_-]{43}/complete$|

    assert Repo.get_by!(Participation, prolific_session_id: attrs.prolific_session_id).status ==
             :completed
  end

  test "renders binary shortcuts and redirects to Prolific after the final answer", %{conn: conn} do
    condition = condition_fixture(:binary_question)
    run_fixture(condition)
    attrs = participation_attrs(condition)
    {_entry_conn, participant_path} = launch_study(conn, condition, attrs)
    {:ok, view, _html} = live(recycle(conn), participant_path)

    view |> element("#accept-consent") |> render_click()

    assert has_element?(view, "#single-post")
    assert has_element?(view, "#question-1[data-state='active']")
    assert has_element?(view, "#question-1-region #answer-yes[data-shortcut='a']")
    assert has_element?(view, "#question-1-region #answer-no[data-shortcut='s']")
    assert has_element?(view, "#binary-skip > #answer-skip[data-shortcut='x']")

    view |> element("#answer-yes") |> render_click()

    assert {completion_path, %{}} = assert_redirect(view)
    assert completion_path =~ ~r|^/participate/[A-Za-z0-9_-]{43}/complete$|
    participation = Repo.get_by!(Participation, prolific_session_id: attrs.prolific_session_id)
    assert participation.status == :completed
  end

  test "a completed participant revisit gets the keyboard-accessible Prolific fallback", %{
    conn: conn
  } do
    condition = condition_fixture(:binary_question)
    run_fixture(condition)
    attrs = participation_attrs(condition)
    {_entry_conn, participant_path} = launch_study(conn, condition, attrs)
    {:ok, view, _html} = live(recycle(conn), participant_path)

    view |> element("#accept-consent") |> render_click()
    view |> element("#answer-skip") |> render_click()
    assert_redirect(view)

    {:ok, revisited, _html} = live(recycle(conn), participant_path)
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

    render_click(view, "answer", %{
      "choice" => "post_a",
      "position" => "99",
      "question_key" => "test-comparison.v1"
    })

    assert has_element?(view, "#task-progress", "1 / 2")
    assert Repo.aggregate(Response, :count) == 0
  end

  test "ignores stale question keys and invalid choices", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition, %{tasks: [psychosocial_task()]})
    attrs = participation_attrs(condition)
    {:ok, view, _html} = enter_study(conn, condition, attrs)
    view |> element("#accept-consent") |> render_click()

    render_click(view, "answer", %{
      "choice" => "post_a",
      "position" => "1",
      "question_key" => "restlessness.v1"
    })

    render_click(view, "answer", %{
      "choice" => "yes",
      "position" => "1",
      "question_key" => "worry.v1"
    })

    assert has_element?(view, "#question-1[data-state='active']")
    assert Repo.aggregate(Response, :count) == 0
  end

  defp psychosocial_task(position \\ 1, post_a \\ "First post", post_b \\ "Second post") do
    %{
      position: position,
      questionnaire_key: "psychosocial-comparisons.v1",
      stimuli: %{
        "post_a" => %{"text" => post_a},
        "post_b" => %{"text" => post_b}
      }
    }
  end

  defp answer_three_questions(view) do
    view |> element("#answer-post-a") |> render_click()
    view |> element("#answer-post-a") |> render_click()
    view |> element("#answer-post-a") |> render_click()
  end

  defp enter_study(conn, condition, attrs) do
    {conn, participant_path} = launch_study(conn, condition, attrs)
    live(recycle(conn), participant_path)
  end

  defp launch_study(conn, condition, attrs) do
    conn =
      get(
        conn,
        ~p"/enter/#{condition.entry_token}?#{%{"PROLIFIC_PID" => attrs.prolific_participant_id, "STUDY_ID" => attrs.prolific_study_id, "SESSION_ID" => attrs.prolific_session_id}}"
      )

    participant_path = redirected_to(conn)
    assert participant_path =~ ~r|^/participate/[A-Za-z0-9_-]{43}$|
    {conn, participant_path}
  end
end
