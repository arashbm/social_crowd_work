defmodule SocialCrowdWork.Imports.ImportResult do
  @moduledoc """
  Summary returned by both CLI and future admin UI import callers.
  """

  alias SocialCrowdWork.Experiments.ImportBatch

  @enforce_keys [:status, :condition_count, :run_count, :task_count]
  defstruct [:status, :import_batch, :condition_count, :run_count, :task_count]

  @type status :: :validated | :imported | :already_imported
  @type t :: %__MODULE__{
          status: status(),
          import_batch: ImportBatch.t() | nil,
          condition_count: non_neg_integer(),
          run_count: non_neg_integer(),
          task_count: non_neg_integer()
        }
end
