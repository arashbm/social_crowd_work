defmodule SocialCrowdWork.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SocialCrowdWorkWeb.Telemetry,
      SocialCrowdWork.Repo,
      {DNSCluster, query: Application.get_env(:social_crowd_work, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SocialCrowdWork.PubSub},
      # Start a worker by calling: SocialCrowdWork.Worker.start_link(arg)
      # {SocialCrowdWork.Worker, arg},
      # Start to serve requests, typically the last entry
      SocialCrowdWorkWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: SocialCrowdWork.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SocialCrowdWorkWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
