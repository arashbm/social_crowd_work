defmodule SocialCrowdWork.ConsentsTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWork.Consents

  test "fetches the production consent by its immutable key" do
    assert {:ok, SocialCrowdWork.Consents.PsychosocialSignalsConsentV1} =
             Consents.fetch("psychosocial-signals-consent.v1")
  end

  test "fetches configured consent modules by versioned external keys" do
    assert {:ok, SocialCrowdWork.TestConsent} = Consents.fetch("test-consent.v1")
    assert :error = Consents.fetch("unknown.v1")
    assert :error = Consents.fetch(:untrusted_atom)
  end

  test "exposes the participant-facing consent content" do
    consent = Consents.fetch!("test-consent.v1")

    assert %Phoenix.LiveView.Rendered{} = consent.render(%{})
  end

  test "production consent exposes the privacy notice and statements" do
    consent = Consents.fetch!("psychosocial-signals-consent.v1")
    rendered = consent.render(%{})

    assert %Phoenix.LiveView.Rendered{} = rendered
    assert rendered.static |> IO.iodata_to_binary() =~ "research_study_privacy_notice.pdf"
    assert rendered.static |> IO.iodata_to_binary() =~ "I give my consent to participate"
  end
end
