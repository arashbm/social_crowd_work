defmodule SocialCrowdWork.Instructions do
  @moduledoc """
  Registry for immutable instruction sets known to the application.

  Production definitions are listed here. Other environments may add
  definitions through `:social_crowd_work, :instruction_set_modules`.
  """

  @instruction_set_modules []

  def fetch(key) when is_binary(key) do
    case Enum.find(instruction_set_modules(), fn module -> module.key() == key end) do
      nil -> :error
      module -> {:ok, module}
    end
  end

  def fetch(_key), do: :error

  def fetch!(key) do
    case fetch(key) do
      {:ok, module} -> module
      :error -> raise KeyError, key: key, term: instruction_set_keys()
    end
  end

  def all, do: instruction_set_modules()

  def instruction_set_keys do
    Enum.map(instruction_set_modules(), & &1.key())
  end

  def validate!(modules) when is_list(modules) do
    definitions = Enum.map(modules, &validate_instruction_set!/1)
    ensure_unique_keys!(definitions, "instruction set")
    :ok
  end

  defp instruction_set_modules do
    modules =
      @instruction_set_modules ++
        Application.get_env(:social_crowd_work, :instruction_set_modules, [])

    validate!(modules)
    modules
  end

  defp validate_instruction_set!(module) do
    key = validate_key!(module, "instruction set")
    pages = module.pages()

    if pages == [] do
      raise ArgumentError, "instruction set #{inspect(key)} must contain at least one page"
    end

    unless is_list(pages) do
      raise ArgumentError, "instruction set #{inspect(key)} pages must be a list"
    end

    page_definitions = Enum.map(pages, &{validate_key!(&1, "instruction page"), &1})
    ensure_unique_keys!(page_definitions, "instruction page in set #{inspect(key)}")
    {key, module}
  end

  defp validate_key!(module, type) do
    key = module.key()

    if is_binary(key) and String.trim(key) != "" do
      key
    else
      raise ArgumentError, "#{type} #{inspect(module)} must have a nonempty string key"
    end
  end

  defp ensure_unique_keys!(definitions, type) do
    duplicate_keys =
      definitions
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.filter(fn {_key, entries} -> length(entries) > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicate_keys != [] do
      raise ArgumentError, "duplicate #{type} keys: #{Enum.join(duplicate_keys, ", ")}"
    end
  end
end
