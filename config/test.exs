import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :mtg_deck_builder, MtgDeckBuilder.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mtg_deck_builder_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :mtg_deck_builder, MtgDeckBuilderWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "PFPlwmMyB9NL8RHfkGPcV2aOuWxwlKowSQ/Z+78RVYeHGkoL5VLy+HTzHWfSlhl2",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Disable card sync in test
config :mtg_deck_builder, MtgDeckBuilder.Cards.CardSyncWorker,
  enabled: false
