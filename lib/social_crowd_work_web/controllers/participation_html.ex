defmodule SocialCrowdWorkWeb.ParticipationHTML do
  use SocialCrowdWorkWeb, :html

  embed_templates "participation_html/*"

  def entry_error_reference(:unknown_condition), do: "invalid-link"
  def entry_error_reference(:invalid_prolific_parameters), do: "missing-participant-details"
  def entry_error_reference(:prolific_study_mismatch), do: "study-mismatch"
  def entry_error_reference(:capacity_reached), do: "too-many-open-studies"
  def entry_error_reference(_reason), do: "entry-error"
end
