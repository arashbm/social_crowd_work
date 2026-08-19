defmodule SocialCrowdWorkWeb.PageController do
  use SocialCrowdWorkWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/admin")
  end
end
