defmodule PuckProWeb.Router do
  use PuckProWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PuckProWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PuckProWeb do
    pipe_through :browser

    # Dashboard
    live "/", DashboardLive, :index

    # Training Plans
    live "/plans", PlansLive, :index
    live "/plans/:slug", PlanLive, :show

    # Drills
    live "/drills", DrillsLive, :index
    live "/drills/:slug", DrillLive, :show
    live "/practice/random", RandomPracticeLive, :index

    # Sessions
    live "/sessions", SessionsLive, :index
    live "/sessions/:id", SessionLive, :show
    live "/practice", PracticeLive, :index

    # Progress & Stats
    live "/progress", ProgressLive, :index
    live "/achievements", AchievementsLive, :index
  end
end
