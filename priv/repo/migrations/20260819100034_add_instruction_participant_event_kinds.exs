defmodule SocialCrowdWork.Repo.Migrations.AddInstructionParticipantEventKinds do
  use Ecto.Migration

  def up do
    drop constraint(:participant_events, :participant_events_kind_valid)

    create constraint(:participant_events, :participant_events_kind_valid,
             check:
               "kind IN ('client_context', 'task_rendered', 'question_rendered', " <>
                 "'question_exposure', 'instruction_rendered', 'instruction_exposure', " <>
                 "'instruction_page_advanced', 'instructions_completed', " <>
                 "'visibility_hidden', 'visibility_visible', 'window_blurred', " <>
                 "'window_focused', 'copy', 'answer_created', 'answer_changed')"
           )
  end

  def down do
    drop constraint(:participant_events, :participant_events_kind_valid)

    create constraint(:participant_events, :participant_events_kind_valid,
             check:
               "kind IN ('client_context', 'task_rendered', 'question_rendered', " <>
                 "'question_exposure', 'visibility_hidden', 'visibility_visible', " <>
                 "'window_blurred', 'window_focused', 'copy', 'answer_created', " <>
                 "'answer_changed')"
           )
  end
end
