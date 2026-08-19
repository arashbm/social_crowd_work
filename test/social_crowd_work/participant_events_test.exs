defmodule SocialCrowdWork.ParticipantEventsTest do
  use SocialCrowdWork.DataCase, async: true

  alias SocialCrowdWork.DataCollection
  alias SocialCrowdWork.DataCollection.ParticipantEvent
  alias SocialCrowdWork.ParticipantEvents

  import SocialCrowdWork.Fixtures

  describe "ingest/2" do
    test "persists a valid batch with server-owned participation and is idempotent" do
      {participation, task} = participant_and_task()
      event_id = Ecto.UUID.generate()

      event = %{
        "event_id" => event_id,
        "kind" => "question_rendered",
        "task_id" => task.id,
        "question_key" => "test-comparison.v1",
        "client_session_id" => Ecto.UUID.generate(),
        "sequence" => 0,
        "client_elapsed_ms" => 12,
        "metadata" => %{}
      }

      assert {:ok, %{accepted_ids: [^event_id], accepted: 1, inserted: 1}} =
               ParticipantEvents.ingest_batch(participation, [event])

      assert {:ok, %{accepted_ids: [^event_id], accepted: 1, inserted: 0}} =
               ParticipantEvents.ingest_batch(participation, [event])

      stored = Repo.get_by!(ParticipantEvent, event_id: event_id)
      assert stored.participant_id == participation.id
      assert stored.task_id == task.id
      assert stored.server_received_at
      assert stored.inserted_at
    end

    test "rejects oversized batches, server fields, foreign tasks, questions, and metadata" do
      {participation, task} = participant_and_task()
      {other_participation, other_task} = participant_and_task()

      assert {:error, :batch_too_large} =
               ParticipantEvents.ingest(participation, List.duplicate(%{}, 26))

      base = %{
        "event_id" => Ecto.UUID.generate(),
        "kind" => "task_rendered",
        "task_id" => task.id
      }

      assert {:error, {:invalid_event, 0, {:unknown_fields, ["participant_id"]}}} =
               ParticipantEvents.ingest(participation, [
                 Map.put(base, "participant_id", other_participation.id)
               ])

      assert {:error, {:invalid_event, 0, %{task_id: [_message]}}} =
               ParticipantEvents.ingest(participation, [%{base | "task_id" => other_task.id}])

      invalid_question =
        base
        |> Map.put("kind", "question_rendered")
        |> Map.put("question_key", "not-in-questionnaire")

      assert {:error, {:invalid_event, 0, %{question_key: [_message]}}} =
               ParticipantEvents.ingest(participation, [invalid_question])

      assert {:error, {:invalid_event, 0, %{metadata: [_message]}}} =
               ParticipantEvents.ingest(participation, [
                 Map.put(base, "metadata", %{"extra" => true})
               ])

      assert Repo.aggregate(ParticipantEvent, :count) == 0
    end

    test "rejects client answer events and out-of-range timing values" do
      {participation, task} = participant_and_task()

      answer = %{
        "event_id" => Ecto.UUID.generate(),
        "kind" => "answer_created",
        "task_id" => task.id,
        "question_key" => "test-comparison.v1",
        "metadata" => %{"previous_choice" => nil, "new_choice" => "post_a"}
      }

      assert {:error, {:invalid_event, 0, %{kind: [_message]}}} =
               ParticipantEvents.ingest(participation, [answer])

      timing = %{
        "event_id" => Ecto.UUID.generate(),
        "kind" => "visibility_hidden",
        "duration_ms" => 604_800_001
      }

      assert {:error, {:invalid_event, 0, %{duration_ms: [_message]}}} =
               ParticipantEvents.ingest(participation, [timing])
    end
  end

  describe "answer events" do
    test "records create and change in the response transaction but not same-choice retries" do
      {participation, task} = participant_and_task()

      assert {:ok, _response} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :post_a
               )

      assert {:ok, _response} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :post_b
               )

      assert {:ok, _response} =
               DataCollection.record_response(
                 participation,
                 task.id,
                 "test-comparison.v1",
                 :post_b
               )

      events = Repo.all(ParticipantEvent)
      assert Enum.map(events, & &1.kind) == [:answer_created, :answer_changed]
      assert Enum.at(events, 0).metadata == %{"previous_choice" => nil, "new_choice" => "post_a"}

      assert Enum.at(events, 1).metadata == %{
               "previous_choice" => "post_a",
               "new_choice" => "post_b"
             }

      assert Enum.all?(
               events,
               &(&1.task_id == task.id and &1.question_key == "test-comparison.v1")
             )
    end
  end

  describe "instruction events" do
    test "accepts strict render and exposure metadata and rejects server progress kinds" do
      condition = condition_fixture(:comparison, %{instructions_key: "test-instructions.v1"})
      run_fixture(condition)
      assert {:ok, participation} = assign(condition)

      identity = %{
        "instructions_key" => "test-instructions.v1",
        "page_key" => "test-instructions-introduction.v1",
        "page_number" => 1
      }

      rendered = %{
        "event_id" => Ecto.UUID.generate(),
        "kind" => "instruction_rendered",
        "metadata" => identity
      }

      exposure = %{
        "event_id" => Ecto.UUID.generate(),
        "kind" => "instruction_exposure",
        "duration_ms" => 500,
        "metadata" =>
          Map.merge(identity, %{
            "visible_ms" => 400,
            "focused_ms" => 350,
            "reason" => "page_unloaded"
          })
      }

      assert {:ok, %{inserted: 2}} = ParticipantEvents.ingest(participation, [rendered, exposure])

      assert {:error, {:invalid_event, 0, %{metadata: [_message]}}} =
               ParticipantEvents.ingest(participation, [
                 put_in(rendered, ["metadata", "page_number"], 2)
               ])

      assert {:error, {:invalid_event, 0, %{kind: [_message]}}} =
               ParticipantEvents.ingest(participation, [
                 %{rendered | "kind" => "instruction_page_advanced"}
               ])
    end

    test "server progress helper appends raw page identity without calculating progress" do
      condition = condition_fixture(:comparison, %{instructions_key: "test-instructions.v1"})
      run_fixture(condition)
      assert {:ok, participation} = assign(condition)

      event =
        ParticipantEvents.insert_instruction_progress_event!(
          participation,
          :instruction_page_advanced,
          "test-instructions-introduction.v1",
          1
        )

      assert event.kind == :instruction_page_advanced

      assert event.metadata == %{
               "instructions_key" => "test-instructions.v1",
               "page_key" => "test-instructions-introduction.v1",
               "page_number" => 1
             }

      assert Repo.get!(DataCollection.Participation, participation.id).instruction_pages_completed ==
               0
    end
  end

  defp participant_and_task do
    condition = condition_fixture()
    run = run_fixture(condition)

    assert {:ok, participation} =
             DataCollection.consent_and_assign_run(
               condition,
               participation_attrs(condition),
               "test-consent.v1"
             )

    {participation, hd(run.tasks)}
  end

  defp assign(condition) do
    DataCollection.consent_and_assign_run(
      condition,
      participation_attrs(condition),
      "test-consent.v1"
    )
  end
end
