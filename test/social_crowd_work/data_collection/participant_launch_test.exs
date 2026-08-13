defmodule SocialCrowdWork.DataCollection.ParticipantLaunchTest do
  use SocialCrowdWork.DataCase, async: true

  alias SocialCrowdWork.DataCollection.ParticipantLaunch

  import SocialCrowdWork.Fixtures

  describe "token primitives" do
    test "generates a URL-safe 32-byte token and its SHA-256 hash" do
      {raw_token, token_hash} = ParticipantLaunch.generate_token()

      assert byte_size(raw_token) == 43
      assert raw_token =~ ~r/^[A-Za-z0-9_-]+$/
      assert byte_size(token_hash) == 32
      assert {:ok, decoded} = ParticipantLaunch.decode_token(raw_token)
      assert byte_size(decoded) == 32
      assert {:ok, ^token_hash} = ParticipantLaunch.hash_token(raw_token)
    end

    test "safely rejects malformed and incorrectly sized tokens" do
      for token <- [nil, "", "not+url/safe", Base.url_encode64("short", padding: false)] do
        assert ParticipantLaunch.decode_token(token) == :error
        assert ParticipantLaunch.hash_token(token) == :error
      end
    end
  end

  describe "changeset" do
    test "injects trusted fields and does not cast programmatic fields from attrs" do
      condition = condition_fixture()
      {_raw_token, token_hash} = ParticipantLaunch.generate_token()
      attrs = valid_attrs()

      changeset =
        ParticipantLaunch.create_changeset(
          condition,
          nil,
          token_hash,
          Map.merge(attrs, %{condition_id: -1, participation_id: -1, token_hash: <<0>>})
        )

      assert changeset.valid?
      assert get_field(changeset, :condition_id) == condition.id
      assert get_field(changeset, :participation_id) == nil
      assert get_field(changeset, :token_hash) == token_hash
    end

    test "validates identifiers and token hash length" do
      condition = condition_fixture()

      changeset =
        ParticipantLaunch.create_changeset(condition, nil, <<0>>, %{
          valid_attrs()
          | prolific_participant_id: " ",
            prolific_study_id: String.duplicate("x", 256)
        })

      errors = errors_on(changeset)
      assert "should be 32 byte(s)" in errors.token_hash
      assert "can't be blank" in errors.prolific_participant_id
      assert "should be at most 255 character(s)" in errors.prolific_study_id
    end

    test "reports unique token and expiry database constraints" do
      condition = condition_fixture()
      {_raw_token, token_hash} = ParticipantLaunch.generate_token()

      assert {:ok, launch} =
               condition
               |> ParticipantLaunch.create_changeset(nil, token_hash, valid_attrs())
               |> Repo.insert()

      assert {:error, duplicate_changeset} =
               condition
               |> ParticipantLaunch.create_changeset(
                 nil,
                 token_hash,
                 valid_attrs(%{prolific_session_id: "another-session"})
               )
               |> Repo.insert()

      assert "has already been taken" in errors_on(duplicate_changeset).token_hash

      assert {:error, expiry_changeset} =
               condition
               |> ParticipantLaunch.create_changeset(
                 nil,
                 elem(ParticipantLaunch.generate_token(), 1),
                 valid_attrs(%{expires_at: DateTime.add(launch.inserted_at, -1, :second)})
               )
               |> Repo.insert()

      assert "is invalid" in errors_on(expiry_changeset).expires_at
    end

    test "reports foreign key and nonblank database constraints" do
      {_raw_token, token_hash} = ParticipantLaunch.generate_token()

      assert {:error, foreign_key_changeset} =
               %ParticipantLaunch{condition_id: -1, token_hash: token_hash}
               |> ParticipantLaunch.changeset(valid_attrs())
               |> Repo.insert()

      assert "does not exist" in errors_on(foreign_key_changeset).condition_id

      condition = condition_fixture()

      assert {:error, blank_changeset} =
               condition
               |> ParticipantLaunch.create_changeset(
                 nil,
                 elem(ParticipantLaunch.generate_token(), 1),
                 valid_attrs()
               )
               |> put_change(:prolific_session_id, " ")
               |> Repo.insert()

      assert "is invalid" in errors_on(blank_changeset).prolific_session_id
    end
  end

  describe "expired?/2" do
    test "treats expiry at or before the comparison time as expired" do
      now = ~U[2026-08-14 12:00:00Z]

      assert ParticipantLaunch.expired?(%ParticipantLaunch{expires_at: now}, now)

      assert ParticipantLaunch.expired?(
               %ParticipantLaunch{expires_at: DateTime.add(now, -1, :second)},
               now
             )

      refute ParticipantLaunch.expired?(
               %ParticipantLaunch{expires_at: DateTime.add(now, 1, :second)},
               now
             )
    end
  end

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        prolific_participant_id: "participant-1",
        prolific_study_id: "study-1",
        prolific_session_id: "session-1",
        expires_at:
          DateTime.utc_now() |> DateTime.add(3_600, :second) |> DateTime.truncate(:second)
      },
      overrides
    )
  end
end
