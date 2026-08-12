defmodule SocialCrowdWorkWeb.ParticipantContexts do
  @moduledoc false

  @session_key "participant_contexts"
  @max_contexts 2
  @max_age_seconds 24 * 60 * 60
  @token_bytes 32
  @token_pattern ~r/^[A-Za-z0-9_-]{43}$/
  @context_keys ~w(condition_id prolific_participant_id prolific_study_id prolific_session_id issued_at)

  def session_key, do: @session_key

  def fetch(session, token) when is_map(session) and is_binary(token) do
    with true <- Regex.match?(@token_pattern, token),
         contexts when is_map(contexts) <- Map.get(session, @session_key),
         context when is_map(context) <- Map.get(contexts, token),
         true <- valid_context?(context) do
      {:ok, context}
    else
      _other -> :error
    end
  end

  def fetch(_session, _token), do: :error

  def put(contexts, context, now \\ System.system_time(:second))

  def put(contexts, context, now)
      when is_map(context) and is_integer(now) do
    contexts = normalize(contexts, now)
    context = Map.put(context, "issued_at", now)

    with true <- valid_context?(context) do
      case existing_token(contexts, context) do
        nil when map_size(contexts) < @max_contexts ->
          token = unique_token(contexts)
          {:ok, Map.put(contexts, token, context), token}

        nil ->
          {:error, :capacity_reached}

        token ->
          {:ok, contexts, token}
      end
    else
      false -> {:error, :invalid_context}
    end
  end

  def put(_contexts, _context, _now), do: {:error, :invalid_context}

  def delete(contexts, token) when is_map(contexts) and is_binary(token),
    do: Map.delete(contexts, token)

  def delete(_contexts, _token), do: %{}

  defp normalize(contexts, now) when is_map(contexts) do
    Map.new(contexts, fn {token, context} -> {token, context} end)
    |> Enum.filter(fn {token, context} ->
      is_binary(token) and Regex.match?(@token_pattern, token) and valid_context?(context) and
        context["issued_at"] > now - @max_age_seconds
    end)
    |> Map.new()
  end

  defp normalize(_contexts, _now), do: %{}

  defp valid_context?(context) when is_map(context) do
    Map.keys(context) |> Enum.sort() == Enum.sort(@context_keys) and
      is_integer(context["condition_id"]) and context["condition_id"] > 0 and
      is_integer(context["issued_at"]) and
      Enum.all?(~w(prolific_participant_id prolific_study_id prolific_session_id), fn key ->
        is_binary(context[key]) and context[key] != ""
      end)
  end

  defp valid_context?(_context), do: false

  defp existing_token(contexts, context) do
    identity = Map.drop(context, ["issued_at"])

    Enum.find_value(contexts, fn {token, stored_context} ->
      if Map.drop(stored_context, ["issued_at"]) == identity, do: token
    end)
  end

  defp unique_token(contexts) do
    token = @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    if Map.has_key?(contexts, token), do: unique_token(contexts), else: token
  end
end
