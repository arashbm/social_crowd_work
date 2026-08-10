defmodule SocialCrowdWorkWeb.AdminPanelTest do
  use SocialCrowdWorkWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SocialCrowdWork.AdminsFixtures
  import SocialCrowdWork.Fixtures

  alias SocialCrowdWork.AdminAudit.AuditEvent
  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.DataCollection.{Participation, Response}
  alias SocialCrowdWork.Experiments.{Condition, ImportBatch, Run}
  alias SocialCrowdWork.Repo

  setup %{conn: conn} do
    admin = admin_fixture()
    %{conn: log_in_admin(conn, admin), admin: admin}
  end

  test "unauthenticated admin routes redirect at the router", %{conn: conn} do
    conn = conn |> delete_session(:admin_token) |> get(~p"/admin")
    assert redirected_to(conn) == ~p"/admins/log-in"
  end

  test "dashboard renders operational metrics and admin navigation", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition)

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#admin-stats")
    assert has_element?(view, "#dashboard-conditions #condition-#{condition.id}")
    assert has_element?(view, "nav a[href='/admin/imports']")
    assert has_element?(view, "a[href='/admins/log-out']")
  end

  test "condition configuration and lifecycle changes are audited", %{conn: conn} do
    condition = condition_fixture(:comparison, %{status: :draft})
    run_fixture(condition)
    {:ok, view, _html} = live(conn, ~p"/admin/conditions/#{condition.id}")

    view
    |> form("#condition-config-form",
      condition: %{
        prolific_study_id: "configured-study",
        prolific_completion_code: "CONFIGURED",
        consent_key: "test-consent.v1"
      }
    )
    |> render_submit()

    assert Repo.get!(Condition, condition.id).prolific_study_id == "configured-study"
    view |> element("#set-status-active") |> render_click()
    assert Repo.get!(Condition, condition.id).status == :active
    assert Repo.aggregate(AuditEvent, :count) == 2
    assert has_element?(view, "#condition-entry-url")
    assert has_element?(view, "#condition-runs")
  end

  test "imports a valid uploaded manifest transactionally and records an audit event", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/imports")
    key = "admin-import-#{System.unique_integer([:positive, :monotonic])}"

    contents =
      Jason.encode!(%{
        "format_version" => "1",
        "conditions" => [
          %{
            "key" => key,
            "task_type" => "comparison",
            "variants" => %{"phase" => "admin-test"},
            "runs" => [
              %{
                "key" => "run-001",
                "tasks" => [
                  %{
                    "position" => 1,
                    "prompt_key" => "test-comparison.v1",
                    "stimuli" => %{
                      "post_a" => %{"text" => "First"},
                      "post_b" => %{"text" => "Second"}
                    }
                  }
                ]
              }
            ]
          }
        ]
      })

    upload =
      file_input(view, "#manifest-upload-form", :manifest, [
        %{name: "admin-test.json", content: contents, type: "application/json"}
      ])

    assert render_upload(upload, "admin-test.json")
    view |> form("#manifest-upload-form") |> render_submit()

    assert has_element?(view, "#import-success")
    assert Repo.get_by!(Condition, key: key).status == :draft
    assert Repo.aggregate(ImportBatch, :count) == 1
    assert Repo.get_by!(AuditEvent, action: "manifest_imported")
  end

  test "participation lists mask IDs while details reveal them", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition)

    attrs =
      participation_attrs(condition, %{prolific_participant_id: "participant-sensitive-123456"})

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    {:ok, index, _html} = live(conn, ~p"/admin/participations")
    assert has_element?(index, "#participations", "part...3456")
    refute has_element?(index, "#participations", attrs.prolific_participant_id)

    {:ok, show, _html} = live(conn, ~p"/admin/participations/#{participation.id}")
    assert has_element?(show, "#raw-prolific-participant-id", attrs.prolific_participant_id)
  end

  test "definitions and authenticated JSONL exports are available", %{conn: conn} do
    condition = condition_fixture()
    run = run_fixture(condition)
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    assert {:ok, _response} =
             DataCollection.record_response(participation, hd(run.tasks).id, :skip)

    {:ok, definitions, _html} = live(conn, ~p"/admin/definitions")
    assert has_element?(definitions, "[id='prompt-test-comparison.v1']")
    assert has_element?(definitions, "[id='consent-test-consent.v1']")

    assert has_element?(
             definitions,
             "[id='consent-psychosocial-signals-consent.v1'] #privacy-notice-document[src='/documents/research_study_privacy_notice.pdf']"
           )

    conn = get(conn, ~p"/admin/exports/download?#{%{condition: condition.key}}")
    body = response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-ndjson"
    assert Jason.decode!(String.trim(body))["condition"]["key"] == condition.key
    assert Repo.get_by!(AuditEvent, action: "responses_exported")
  end

  test "run details are read-only and show imported task payloads", %{conn: conn} do
    condition = condition_fixture()
    run = run_fixture(condition)
    {:ok, view, _html} = live(conn, ~p"/admin/runs/#{run.id}")

    assert has_element?(view, "#run-tasks")
    assert has_element?(view, "#run-tasks", "test-comparison.v1")
    refute has_element?(view, "#run-tasks form")
    assert Repo.aggregate(Run, :count) == 1
  end

  test "response data remains immutable from admin pages", %{conn: conn} do
    condition = condition_fixture()
    run_fixture(condition)
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    {:ok, view, _html} = live(conn, ~p"/admin/participations/#{participation.id}")
    refute has_element?(view, "#participation-responses form")
    assert Repo.aggregate(Response, :count) == 0
    assert Repo.aggregate(Participation, :count) == 1
  end
end
