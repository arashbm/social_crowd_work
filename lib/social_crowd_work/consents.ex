defmodule SocialCrowdWork.Consents do
  @moduledoc """
  Registry for immutable consent modules known to the application.

  Production definitions will be listed here. Tests add definitions through
  `:social_crowd_work, :consent_modules` so placeholder wording cannot be used
  by the deployed application.
  """

  @consent_modules []

  def fetch(key) when is_binary(key) do
    case Enum.find(consent_modules(), fn module -> module.key() == key end) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  def fetch(_key), do: :error

  def fetch!(key) do
    case fetch(key) do
      {:ok, module} -> module
      :error -> raise KeyError, key: key, term: consent_keys()
    end
  end

  def all, do: consent_modules()

  def consent_keys do
    Enum.map(consent_modules(), & &1.key())
  end

  defp consent_modules do
    modules = @consent_modules ++ Application.get_env(:social_crowd_work, :consent_modules, [])
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
      raise ArgumentError, "duplicate consent keys: #{Enum.join(duplicate_keys, ", ")}"
    end
  end
end
