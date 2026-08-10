defmodule SocialCrowdWork.Repo do
  use Ecto.Repo,
    otp_app: :social_crowd_work,
    adapter: Ecto.Adapters.Postgres
end
