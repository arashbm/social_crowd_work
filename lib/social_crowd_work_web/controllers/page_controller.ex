defmodule SocialCrowdWorkWeb.PageController do
  use SocialCrowdWorkWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
