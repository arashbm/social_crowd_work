defmodule SocialCrowdWorkWeb.ParticipantContextsTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWorkWeb.ParticipantContexts

  test "creates opaque tokens and fetches their exact contexts" do
    assert {:ok, contexts, token} = ParticipantContexts.put(%{}, context(), 1_000)
    assert token =~ ~r/^[A-Za-z0-9_-]{43}$/

    assert {:ok, stored} =
             ParticipantContexts.fetch(%{ParticipantContexts.session_key() => contexts}, token)

    assert stored["prolific_session_id"] == "session-1"
  end

  test "reuses identical contexts and separates different sessions" do
    assert {:ok, contexts, first_token} = ParticipantContexts.put(%{}, context(), 1_000)
    assert {:ok, ^contexts, ^first_token} = ParticipantContexts.put(contexts, context(), 1_001)

    second = Map.put(context(), "prolific_session_id", "session-2")
    assert {:ok, contexts, second_token} = ParticipantContexts.put(contexts, second, 1_001)
    assert first_token != second_token
    assert map_size(contexts) == 2
  end

  test "prunes stale contexts before enforcing capacity" do
    assert {:ok, contexts, _token} = ParticipantContexts.put(%{}, context(), 1)
    later = 24 * 60 * 60 + 2
    second = Map.put(context(), "prolific_session_id", "session-2")

    assert {:ok, contexts, _token} = ParticipantContexts.put(contexts, second, later)
    assert map_size(contexts) == 1
  end

  test "rejects a third fresh context" do
    assert {:ok, contexts, _token} = ParticipantContexts.put(%{}, context(), 1_000)

    assert {:ok, contexts, _token} =
             ParticipantContexts.put(
               contexts,
               Map.put(context(), "prolific_session_id", "session-2"),
               1_001
             )

    assert {:error, :capacity_reached} =
             ParticipantContexts.put(
               contexts,
               Map.put(context(), "prolific_session_id", "session-3"),
               1_002
             )
  end

  test "rejects malformed tokens and contexts" do
    assert :error = ParticipantContexts.fetch(%{}, "not-a-token")
    assert {:error, :invalid_context} = ParticipantContexts.put(%{}, %{}, 1_000)
  end

  defp context do
    %{
      "condition_id" => 1,
      "prolific_participant_id" => "participant",
      "prolific_study_id" => "study",
      "prolific_session_id" => "session-1"
    }
  end
end
