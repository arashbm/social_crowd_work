defmodule SocialCrowdWork.Repo.Migrations.AddInstructionSets do
  use Ecto.Migration

  def change do
    alter table(:conditions) do
      add :instructions_key, :string
    end

    alter table(:participations) do
      add :instructions_key, :string
      add :instruction_pages_completed, :integer, null: false, default: 0
      add :instructions_completed_at, :utc_datetime
    end

    create constraint(:conditions, :conditions_instructions_key_not_blank,
             check: "instructions_key IS NULL OR btrim(instructions_key) <> ''"
           )

    create constraint(:participations, :participations_instructions_key_not_blank,
             check: "instructions_key IS NULL OR btrim(instructions_key) <> ''"
           )

    create constraint(
             :participations,
             :participations_instruction_pages_completed_nonnegative,
             check: "instruction_pages_completed >= 0"
           )

    create constraint(:participations, :participations_instructions_consistent,
             check:
               "instructions_key IS NOT NULL OR " <>
                 "(instruction_pages_completed = 0 AND instructions_completed_at IS NULL)"
           )
  end
end
