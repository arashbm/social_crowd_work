defmodule SocialCrowdWorkWeb.AdminExportController do
  use SocialCrowdWorkWeb, :controller

  alias SocialCrowdWork.{AdminAudit, Exports}

  def download(conn, params) do
    condition_key = non_blank(params["condition"])

    filename =
      if condition_key,
        do: "responses-#{safe_filename(condition_key)}.jsonl",
        else: "responses-all.jsonl"

    {:ok, _event} =
      AdminAudit.record(conn.assigns.current_scope, "responses_exported",
        target_type: "export",
        metadata: %{"condition_key" => condition_key || "all"}
      )

    conn =
      conn
      |> put_resp_content_type("application/x-ndjson")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_chunked(200)

    opts = if condition_key, do: [condition_key: condition_key], else: []

    case Exports.reduce_jsonl(conn, &write_chunk/2, opts) do
      {:ok, conn} -> conn
      {:error, reason} -> raise "JSONL export failed: #{inspect(reason)}"
    end
  end

  defp write_chunk(line, conn) do
    case chunk(conn, line) do
      {:ok, conn} -> conn
      {:error, reason} -> raise "client export stream closed: #{inspect(reason)}"
    end
  end

  defp non_blank(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: value
  end

  defp non_blank(_value), do: nil

  defp safe_filename(value), do: String.replace(value, ~r/[^a-zA-Z0-9_-]/, "-")
end
