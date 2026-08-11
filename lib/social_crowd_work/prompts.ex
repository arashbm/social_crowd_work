defmodule SocialCrowdWork.Prompts do
  @moduledoc """
  Registry for immutable prompt modules known to the application.

  Production prompts will be listed in this module. Additional modules may be
  configured under `:social_crowd_work, :prompt_modules`, which lets tests use
  definitions that cannot accidentally become production research prompts.
  """

  @prompt_modules [
    SocialCrowdWork.Prompts.WorryV1,
    SocialCrowdWork.Prompts.RestlessnessV1,
    SocialCrowdWork.Prompts.CognitiveDisruptionV1
  ]

  def fetch(key) when is_binary(key) do
    case Enum.find(prompt_modules(), fn module -> module.key() == key end) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  def fetch(_key), do: :error

  def fetch!(key) do
    case fetch(key) do
      {:ok, module} -> module
      :error -> raise KeyError, key: key, term: prompt_keys()
    end
  end

  def all, do: prompt_modules()

  def prompt_keys do
    Enum.map(prompt_modules(), & &1.key())
  end

  defp prompt_modules do
    modules = @prompt_modules ++ Application.get_env(:social_crowd_work, :prompt_modules, [])
    ensure_unique_keys!(modules)
    modules
  end

  defp ensure_unique_keys!(modules) do
    duplicate_keys =
      modules
      |> Enum.group_by(& &1.key())
      |> Enum.filter(fn {_key, definitions} -> length(definitions) > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicate_keys != [] do
      raise ArgumentError, "duplicate prompt keys: #{Enum.join(duplicate_keys, ", ")}"
    end
  end
end
