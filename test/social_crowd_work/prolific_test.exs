defmodule SocialCrowdWork.ProlificTest do
  use ExUnit.Case, async: true

  alias SocialCrowdWork.Prolific

  test "builds an encoded URL from the configured Prolific completion endpoint" do
    assert Prolific.completion_url("CODE WITH +") ==
             "https://app.prolific.com/submissions/complete?cc=CODE+WITH+%2B"
  end
end
