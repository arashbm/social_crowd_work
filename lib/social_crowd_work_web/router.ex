defmodule SocialCrowdWorkWeb.Router do
  use SocialCrowdWorkWeb, :router

  import SocialCrowdWorkWeb.AdminAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SocialCrowdWorkWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :participant_privacy do
    plug SocialCrowdWorkWeb.Plugs.ParticipantPrivacy
  end

  scope "/", SocialCrowdWorkWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", SocialCrowdWorkWeb do
    pipe_through [:browser, :participant_privacy]

    get "/enter/:entry_token", ParticipationController, :start
    get "/participate/error", ParticipationController, :error
    get "/participate/declined", ParticipationController, :declined
    delete "/participate/:launch_token/decline", ParticipationController, :decline
    get "/participate/:launch_token/complete", ParticipationController, :complete
    live "/participate/:launch_token", ParticipantLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", SocialCrowdWorkWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:social_crowd_work, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SocialCrowdWorkWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
      get "/prolific-complete", SocialCrowdWorkWeb.DevProlificController, :complete
    end
  end

  ## Authentication routes

  scope "/", SocialCrowdWorkWeb do
    pipe_through [:browser, :require_authenticated_admin]

    live_session :require_authenticated_admin,
      on_mount: [{SocialCrowdWorkWeb.AdminAuth, :require_authenticated}] do
      live "/admins/settings", AdminLive.Settings, :edit
      live "/admins/settings/confirm-email/:token", AdminLive.Settings, :confirm_email
      live "/admin", AdminLive.Dashboard, :index
      live "/admin/imports", AdminLive.Imports, :index
      live "/admin/conditions", AdminLive.ConditionIndex, :index
      live "/admin/conditions/:id", AdminLive.ConditionShow, :show
      live "/admin/runs/:id", AdminLive.RunShow, :show
      live "/admin/participations", AdminLive.ParticipationIndex, :index
      live "/admin/participations/:id", AdminLive.ParticipationShow, :show
      live "/admin/exports", AdminLive.Exports, :index
      live "/admin/definitions", AdminLive.Definitions, :index
      live "/admin/audit", AdminLive.Audit, :index
    end

    post "/admins/update-password", AdminSessionController, :update_password
    get "/admin/exports/download", AdminExportController, :download
  end

  scope "/", SocialCrowdWorkWeb do
    pipe_through [:browser]

    live_session :current_admin,
      on_mount: [{SocialCrowdWorkWeb.AdminAuth, :mount_current_scope}] do
      live "/admins/log-in", AdminLive.Login, :new
    end

    post "/admins/log-in", AdminSessionController, :create
    delete "/admins/log-out", AdminSessionController, :delete
  end
end
