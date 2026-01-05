# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :mtg_deck_builder,
  ecto_repos: [MtgDeckBuilder.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :mtg_deck_builder, MtgDeckBuilderWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MtgDeckBuilderWeb.ErrorHTML, json: MtgDeckBuilderWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MtgDeckBuilder.PubSub,
  live_view: [signing_salt: "GCa3iGM+"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  mtg_deck_builder: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  mtg_deck_builder: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Ueberauth for Google OAuth
config :ueberauth, Ueberauth,
  providers: [
    google: {Ueberauth.Strategy.Google, [default_scope: "email profile"]}
  ]

# Configure Tesla to use Hackney adapter
config :tesla, adapter: {Tesla.Adapter.Hackney, recv_timeout: 60_000}

# Suppress Tesla builder deprecation warning
config :tesla, disable_deprecated_builder_warning: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
