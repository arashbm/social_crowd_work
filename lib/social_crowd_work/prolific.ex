defmodule SocialCrowdWork.Prolific do
  @moduledoc """
  Builds Prolific completion URLs from environment-specific configuration.
  """

  def completion_url(code) when is_binary(code) do
    base_url = Application.fetch_env!(:social_crowd_work, :prolific_completion_url)
    uri = URI.parse(base_url)
    query = uri.query |> decode_query() |> Map.put("cc", code) |> URI.encode_query()

    %{uri | query: query}
    |> URI.to_string()
  end

  defp decode_query(nil), do: %{}
  defp decode_query(query), do: URI.decode_query(query)
end
