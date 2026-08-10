defmodule SocialCrowdWorkWeb.DevProlificController do
  use SocialCrowdWorkWeb, :controller

  def complete(conn, %{"cc" => completion_code}) do
    render(conn, :complete, completion_code: completion_code)
  end

  def complete(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> render(:complete, completion_code: nil)
  end
end
