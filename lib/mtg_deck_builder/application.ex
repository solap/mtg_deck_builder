defmodule MtgDeckBuilder.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MtgDeckBuilderWeb.Telemetry,
      MtgDeckBuilder.Repo,
      {DNSCluster, query: Application.get_env(:mtg_deck_builder, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MtgDeckBuilder.PubSub},
      # Scheduled card data sync
      MtgDeckBuilder.Cards.CardSyncWorker,
      # Chat undo state manager
      MtgDeckBuilder.Chat.UndoServer,
      # Start to serve requests, typically the last entry
      MtgDeckBuilderWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MtgDeckBuilder.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MtgDeckBuilderWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
