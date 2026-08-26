defmodule SocialCrowdWorkWeb.AdminPanelTest do
  use SocialCrowdWorkWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import SocialCrowdWork.AdminsFixtures
  import SocialCrowdWork.Fixtures

  alias SocialCrowdWork.AdminAudit.AuditEvent
  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.DataCollection.{ParticipantEvent, Participation, Response}
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

  test "raw participant telemetry download requires admin authentication", %{conn: conn} do
    conn =
      conn
      |> delete_session(:admin_token)
      |> get(~p"/admin/exports/participant-events/download")

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
    condition =
      condition_fixture(:comparison, %{
        status: :draft,
        instructions_key: "test-instructions.v1"
      })

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
    assert has_element?(view, "#condition-entry-url", "/enter/#{condition.entry_token}")
    assert has_element?(view, "#condition-runs")
    assert has_element?(view, "#condition-instructions-key", "test-instructions.v1")
  end

  test "condition runs are paginated without loading the full inventory", %{conn: conn} do
    condition = condition_fixture()
    import_batch = import_batch_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    runs =
      for number <- 1..27 do
        %{
          condition_id: condition.id,
          import_batch_id: import_batch.id,
          external_key: "run-#{number |> Integer.to_string() |> String.pad_leading(3, "0")}",
          inserted_at: now,
          updated_at: now
        }
      end

    {27, _rows} = Repo.insert_all(Run, runs)

    {:ok, view, _html} = live(conn, ~p"/admin/conditions/#{condition.id}")

    assert has_element?(view, "#condition-runs-range", "1-25 of 27")
    assert has_element?(view, "#condition-runs", "run-001")
    refute has_element?(view, "#condition-runs", "run-026")
    assert has_element?(view, "#condition-runs-pagination", "Page 1 of 2")
    assert has_element?(view, "#condition-runs-previous[aria-disabled='true']")

    view |> element("#condition-runs-next") |> render_click()
    assert_patch(view, ~p"/admin/conditions/#{condition.id}?page=2")

    assert has_element?(view, "#condition-runs-range", "26-27 of 27")
    assert has_element?(view, "#condition-runs", "run-026")
    assert has_element?(view, "#condition-runs", "run-027")
    refute has_element?(view, "#condition-runs", "run-001")
    assert has_element?(view, "#condition-runs-next[aria-disabled='true']")
    assert has_element?(view, "#condition-runs-previous[href*='page=1']")
  end

  test "imports a valid uploaded manifest transactionally and records an audit event", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/imports")
    key = "admin-import-#{System.unique_integer([:positive, :monotonic])}"

    contents =
      Jason.encode!(%{
        "format_version" => "3",
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
                    "questionnaire_key" => "test-comparison.v1",
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

  test "shows oversized manifest errors and prevents submission", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/imports")

    upload =
      file_input(view, "#manifest-upload-form", :manifest, [
        %{
          name: "too-large.json",
          content: String.duplicate("x", 1_001),
          type: "application/json"
        }
      ])

    assert {:error, [[_ref, :too_large]]} = render_upload(upload, "too-large.json", 1)
    assert has_element?(view, "#manifest-upload-errors", "The manifest exceeds 100 MB.")
    assert has_element?(view, "#import-manifest[disabled]")
  end

  test "shows unsupported manifest type errors and prevents submission", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/imports")

    upload =
      file_input(view, "#manifest-upload-form", :manifest, [
        %{name: "manifest.txt", content: "{}", type: "text/plain"}
      ])

    assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "manifest.txt", 1)
    assert has_element?(view, "#manifest-upload-errors", "Only JSON files are accepted.")
    assert has_element?(view, "#import-manifest[disabled]")
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

  test "copies resume links only for resumable participations and audits generation", %{
    conn: conn
  } do
    resumable_condition = condition_fixture()
    run_fixture(resumable_condition)

    assert {:ok, resumable} =
             DataCollection.consent_and_assign_run(
               resumable_condition,
               participation_attrs(resumable_condition),
               "test-consent.v1"
             )

    in_progress_condition = condition_fixture()
    run_fixture(in_progress_condition)

    assert {:ok, in_progress} =
             DataCollection.consent_and_assign_run(
               in_progress_condition,
               participation_attrs(in_progress_condition),
               "test-consent.v1"
             )

    in_progress =
      in_progress
      |> Ecto.Changeset.change(status: :in_progress)
      |> Repo.update!()

    completed_condition = condition_fixture()
    run_fixture(completed_condition)

    assert {:ok, completed} =
             DataCollection.consent_and_assign_run(
               completed_condition,
               participation_attrs(completed_condition),
               "test-consent.v1"
             )

    completed =
      completed
      |> Ecto.Changeset.change(
        status: :completed,
        completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/admin/participations")

    assert has_element?(
             view,
             "#copy-resume-link-#{resumable.id}[data-participation-id='#{resumable.id}']"
           )

    assert has_element?(view, "#copy-resume-link-#{in_progress.id}")
    refute has_element?(view, "#copy-resume-link-#{completed.id}")

    render_hook(view, "copy_resume_link", %{"participation_id" => Integer.to_string(resumable.id)})

    assert Repo.aggregate(DataCollection.ParticipantLaunch, :count) == 1

    audit_event = Repo.get_by!(AuditEvent, action: "participant_resume_link_generated")
    assert audit_event.target_type == "participation"
    assert audit_event.target_id == resumable.id
  end

  test "definitions and authenticated JSONL exports are available", %{conn: conn} do
    condition = condition_fixture()
    run = run_fixture(condition)
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    insert_response(participation, hd(run.tasks), "test-comparison.v1", :skip)

    {:ok, definitions, _html} = live(conn, ~p"/admin/definitions")
    assert has_element?(definitions, "[id='prompt-test-comparison.v1']")
    assert has_element?(definitions, "[id='questionnaire-test-comparison.v1']")

    assert has_element?(
             definitions,
             "[id='questionnaire-psychosocial-comparisons.v1-question-1']",
             "low-mood.v1"
           )

    assert has_element?(
             definitions,
             "[id='questionnaire-psychosocial-comparisons.v1-question-16']",
             "appetite-changes.v1"
           )

    assert has_element?(definitions, "[id='consent-test-consent.v1']")
    assert has_element?(definitions, "[id='instruction-set-test-instructions.v1']")

    assert has_element?(
             definitions,
             "[id='instruction-set-test-instructions.v1-page-1']",
             "test-instructions-introduction.v1"
           )

    assert has_element?(
             definitions,
             "[id='prompt-worry.v1'] #worry-prompt-v1",
             "Which post shows more concern about something bad or uncertain happening?"
           )

    assert has_element?(
             definitions,
             "#worry-prompt-v1 u",
             "concern about something bad or uncertain happening"
           )

    assert has_element?(
             definitions,
             "[id='prompt-restlessness.v1'] #restlessness-prompt-v1",
             "Which post shows more difficulty relaxing or settling down?"
           )

    assert has_element?(
             definitions,
             "#restlessness-prompt-v1 u",
             "difficulty relaxing or settling down"
           )

    assert has_element?(
             definitions,
             "[id='prompt-cognitive-disruption.v1'] #cognitive-disruption-prompt-v1",
             "Which post shows more difficulty thinking clearly or controlling thoughts?"
           )

    assert has_element?(
             definitions,
             "#cognitive-disruption-prompt-v1 u",
             "difficulty thinking clearly or controlling thoughts"
           )

    assert has_element?(
             definitions,
             "[id='consent-psychosocial-signals-consent.v1'] #privacy-notice-document[src='/documents/research_study_privacy_notice.pdf']"
           )

    conn = get(conn, ~p"/admin/exports/download?#{%{condition: condition.key}}")
    body = response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-ndjson"
    export = Jason.decode!(String.trim(body))
    assert export["schema_version"] == "3"
    assert export["condition"]["key"] == condition.key
    assert export["question"] == %{"key" => "test-comparison.v1", "number" => 1}
    assert Repo.get_by!(AuditEvent, action: "responses_exported")
  end

  test "raw participant telemetry links and authenticated download are separate", %{conn: conn} do
    condition = condition_fixture()
    run = run_fixture(condition)
    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    event =
      %ParticipantEvent{
        participant_id: participation.id,
        server_received_at: DateTime.utc_now()
      }
      |> ParticipantEvent.changeset(%{
        task_id: hd(run.tasks).id,
        question_key: "test-comparison.v1",
        kind: :question_rendered,
        event_id: Ecto.UUID.generate(),
        client_session_id: Ecto.UUID.generate(),
        sequence: 1,
        client_elapsed_ms: 25,
        metadata: %{}
      })
      |> Repo.insert!()

    {:ok, exports, _html} = live(conn, ~p"/admin/exports")

    assert has_element?(
             exports,
             "#participant-event-exports",
             "No calculations or derived metrics"
           )

    assert has_element?(exports, "#export-participant-events-all")

    assert has_element?(
             exports,
             "#export-participant-events-condition-#{condition.id} a[href='/admin/exports/participant-events/download?condition=#{condition.key}']"
           )

    conn =
      get(conn, ~p"/admin/exports/participant-events/download?#{%{condition: condition.key}}")

    body = response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-ndjson"

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="participant-events-#{condition.key}.jsonl")
           ]

    export = Jason.decode!(String.trim(body))
    assert export["schema_version"] == "2"
    assert export["event"]["event_id"] == event.event_id
    assert export["participation"]["prolific_participant_id"] == attrs.prolific_participant_id

    audit = Repo.get_by!(AuditEvent, action: "participant_telemetry_exported")
    assert audit.metadata == %{"condition_key" => condition.key}
  end

  test "run details are read-only and show imported task payloads", %{conn: conn} do
    condition = condition_fixture(:comparison, %{instructions_key: "test-instructions.v1"})
    run = run_fixture(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(
               condition,
               participation_attrs(condition),
               "test-consent.v1"
             )

    {:ok, view, _html} = live(conn, ~p"/admin/runs/#{run.id}")

    assert has_element?(view, "#run-tasks")
    assert has_element?(view, "#run-tasks", "test-comparison.v1")
    assert has_element?(view, "#task-#{hd(run.tasks).id}-question-1", "test-comparison.v1")
    assert has_element?(view, "#run-instruction-progress", "test-instructions.v1")

    assert has_element?(
             view,
             "#run-instruction-progress",
             "#{participation.instruction_pages_completed} pages"
           )

    refute has_element?(view, "#run-tasks form")
    assert Repo.aggregate(Run, :count) == 1
  end

  test "response data remains immutable from admin pages", %{conn: conn} do
    condition = condition_fixture()

    run =
      run_fixture(condition, %{
        tasks: [
          %{
            position: 1,
            questionnaire_key: "psychosocial-comparisons.v1",
            stimuli: %{
              "post_a" => %{"text" => "First post"},
              "post_b" => %{"text" => "Second post"}
            }
          }
        ]
      })

    attrs = participation_attrs(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(condition, attrs, "test-consent.v1")

    insert_response(participation, hd(run.tasks), "worry.v1", :post_a)

    {:ok, index, _html} = live(conn, ~p"/admin/participations")
    assert has_element?(index, "#participation-#{participation.id}", "1 / 16 questions")

    {:ok, view, _html} = live(conn, ~p"/admin/participations/#{participation.id}")
    assert has_element?(view, "h1", "Participation #{participation.id}")
    assert has_element?(view, "#task-#{hd(run.tasks).id}-question-1", "low-mood.v1")
    assert has_element?(view, "#task-#{hd(run.tasks).id}-question-2", "hopelessness.v1")
    assert has_element?(view, "#task-#{hd(run.tasks).id}-question-3", "worry.v1")
    refute has_element?(view, "#participation-responses form")
    assert Repo.aggregate(Response, :count) == 1
    assert Repo.aggregate(Participation, :count) == 1
  end

  test "participation details show instruction progress and an explanatory equal label", %{
    conn: conn
  } do
    condition = condition_fixture(:comparison, %{instructions_key: "test-instructions.v1"})
    run = run_fixture(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(
               condition,
               participation_attrs(condition),
               "test-consent.v1"
             )

    participation =
      participation
      |> Ecto.Changeset.change(%{
        instruction_pages_completed: 1,
        instructions_completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.update!()

    insert_response(participation, hd(run.tasks), "test-comparison.v1", :equal)

    {:ok, view, _html} = live(conn, ~p"/admin/participations/#{participation.id}")
    assert has_element?(view, "#participation-instructions-key", "test-instructions.v1")
    assert has_element?(view, "#participation-instruction-progress", "1 pages")
    assert has_element?(view, "#participation-responses", "Very close / neither (equal)")
    refute has_element?(view, "#participation-responses form")
  end

  test "participation task and question responses are paginated", %{conn: conn} do
    condition = condition_fixture()
    run = run_fixture(condition, %{tasks: Enum.map(1..12, &comparison_task/1)})

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(
               condition,
               participation_attrs(condition),
               "test-consent.v1"
             )

    Enum.each(run.tasks, fn task ->
      insert_response(participation, task, "test-comparison.v1", :post_a)
    end)

    {:ok, view, _html} = live(conn, ~p"/admin/participations/#{participation.id}")

    task_1 = Enum.find(run.tasks, &(&1.position == 1))
    task_10 = Enum.find(run.tasks, &(&1.position == 10))
    task_11 = Enum.find(run.tasks, &(&1.position == 11))
    task_12 = Enum.find(run.tasks, &(&1.position == 12))

    assert has_element?(view, "#participation-responses-range", "Tasks 1-10 of 12")
    assert has_element?(view, "#task-#{task_1.id}-question-1")
    assert has_element?(view, "#task-#{task_10.id}-question-1")
    refute has_element?(view, "#task-#{task_11.id}-question-1")
    assert has_element?(view, "#participation-responses-pagination", "Page 1 of 2")
    assert has_element?(view, "#participation-responses-previous[aria-disabled='true']")

    view |> element("#participation-responses-next") |> render_click()
    assert_patch(view, ~p"/admin/participations/#{participation.id}?page=2")

    assert has_element?(view, "#participation-responses-range", "Tasks 11-12 of 12")
    assert has_element?(view, "#task-#{task_11.id}-question-1")
    assert has_element?(view, "#task-#{task_12.id}-question-1")
    refute has_element?(view, "#task-#{task_1.id}-question-1")
    assert has_element?(view, "#participation-responses-next[aria-disabled='true']")
    assert has_element?(view, "#participation-responses-previous[href*='page=1']")
  end

  defp insert_response(participation, task, question_key, choice) do
    %Response{}
    |> Response.changeset(
      %{
        participation_id: participation.id,
        task_id: task.id,
        run_id: participation.run_id,
        question_key: question_key,
        choice: choice,
        answered_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      participation.run.condition.task_type
    )
    |> Repo.insert!()
  end
end
