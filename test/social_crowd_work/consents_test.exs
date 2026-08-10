defmodule SocialCrowdWork.ConsentsTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWork.Consents

  test "fetches configured consent modules by versioned external keys" do
    assert {:ok, SocialCrowdWork.TestConsent} = Consents.fetch("test-consent.v1")
    assert :error = Consents.fetch("unknown.v1")
    assert :error = Consents.fetch(:untrusted_atom)
  end

  test "exposes the participant-facing consent content" do
    consent = Consents.fetch!("test-consent.v1")

    assert %Phoenix.LiveView.Rendered{} = consent.render(%{})
  end
end
