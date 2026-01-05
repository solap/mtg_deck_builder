defmodule MtgDeckBuilderWeb.Router do
  use MtgDeckBuilderWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MtgDeckBuilderWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MtgDeckBuilderWeb.Plugs.FetchCurrentUser
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_admin do
    plug MtgDeckBuilderWeb.Plugs.RequireAdmin
  end

  # Auth routes
  scope "/auth", MtgDeckBuilderWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    delete "/logout", AuthController, :logout
  end

  scope "/", MtgDeckBuilderWeb do
    pipe_through :browser

    live "/", DeckLive, :index
  end

  # Admin routes (protected)
  scope "/admin", MtgDeckBuilderWeb.Admin do
    pipe_through [:browser, :require_admin]

    live "/settings", SettingsLive, :index
    live "/costs", CostsLive, :index
    live "/agents", AgentsLive, :index
    live "/agents/:agent_id", AgentsLive, :show
    live "/providers", ProvidersLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MtgDeckBuilderWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:mtg_deck_builder, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MtgDeckBuilderWeb.Telemetry
    end
  end
end
