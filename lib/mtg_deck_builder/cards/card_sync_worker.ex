defmodule MtgDeckBuilder.Cards.CardSyncWorker do
  @moduledoc """
  Scheduled worker that periodically syncs card data from Scryfall.

  Scryfall updates their bulk data daily, so this worker runs once per day
  by default to keep card data fresh (prices, legalities, new cards).

  ## Configuration

  Configure the sync interval in config:

      config :mtg_deck_builder, MtgDeckBuilder.Cards.CardSyncWorker,
        enabled: true,
        sync_interval_hours: 24

  ## Manual Sync

  Trigger a manual sync:

      MtgDeckBuilder.Cards.CardSyncWorker.sync_now()
  """

  use GenServer
  require Logger

  alias MtgDeckBuilder.Cards.CopyImporter

  @default_interval_hours 24
  # Delay initial sync to let app fully start
  @initial_sync_delay_ms 30_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate sync. Returns :ok.
  """
  def sync_now do
    GenServer.cast(__MODULE__, :sync_now)
  end

  @doc """
  Returns the status of the sync worker.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    config = Application.get_env(:mtg_deck_builder, __MODULE__, [])
    enabled = Keyword.get(config, :enabled, true)
    interval_hours = Keyword.get(config, :sync_interval_hours, @default_interval_hours)
    interval_ms = interval_hours * 60 * 60 * 1000

    state = %{
      enabled: enabled,
      interval_ms: interval_ms,
      last_sync: nil,
      last_sync_result: nil,
      syncing: false
    }

    # Check if we have cards already
    card_count = MtgDeckBuilder.Repo.aggregate(MtgDeckBuilder.Cards.Card, :count)

    if enabled do
      if card_count == 0 do
        # No cards - schedule initial import after a short delay
        # (using COPY protocol, this is now fast enough for production)
        Process.send_after(self(), :initial_sync, @initial_sync_delay_ms)
        Logger.info("CardSyncWorker started - initial import scheduled in #{div(@initial_sync_delay_ms, 1000)}s")
      else
        # Have cards - schedule regular sync
        schedule_sync(interval_ms)
        Logger.info("CardSyncWorker started, next sync in #{interval_hours} hours (#{card_count} cards in DB)")
      end
    else
      Logger.info("CardSyncWorker started - sync disabled (#{card_count} cards in DB)")
    end

    {:ok, state}
  end

  @impl true
  def handle_cast(:sync_now, state) do
    if state.syncing do
      Logger.info("Sync already in progress, skipping manual trigger")
      {:noreply, state}
    else
      {:noreply, do_sync(state)}
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:sync, state) do
    if state.enabled and not state.syncing do
      state = do_sync(state, clear_first: false)
      schedule_sync(state.interval_ms)
      {:noreply, state}
    else
      schedule_sync(state.interval_ms)
      {:noreply, state}
    end
  end

  def handle_info(:initial_sync, state) do
    if not state.syncing do
      Logger.info("Starting initial card import...")
      state = do_sync(state, clear_first: true)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:sync_complete, result}, state) do
    now = DateTime.utc_now()

    state =
      case result do
        {:ok, count} ->
          Logger.info("Card sync completed: #{count} cards imported")
          # Schedule next sync
          schedule_sync(state.interval_ms)
          %{state | syncing: false, last_sync: now, last_sync_result: {:ok, count}}

        {:error, reason} ->
          Logger.error("Card sync failed: #{inspect(reason)}")
          # Retry in 1 hour on failure
          Process.send_after(self(), :sync, 60 * 60 * 1000)
          %{state | syncing: false, last_sync: now, last_sync_result: {:error, reason}}
      end

    {:noreply, state}
  end

  # Private Functions

  defp schedule_sync(interval_ms) do
    Process.send_after(self(), :sync, interval_ms)
  end

  defp do_sync(state, opts \\ []) do
    Logger.info("Starting card data sync from Scryfall (using COPY protocol)...")
    parent = self()
    clear_first = Keyword.get(opts, :clear_first, true)

    # Run sync in a separate process to not block the GenServer
    Task.start(fn ->
      result = CopyImporter.import(
        clear_first: clear_first,
        progress_callback: &sync_progress/2
      )
      send(parent, {:sync_complete, result})
    end)

    %{state | syncing: true}
  end

  defp sync_progress(:downloading, {bytes, total}) when total > 0 do
    percent = round(bytes / total * 100)

    if rem(percent, 10) == 0 do
      Logger.debug("Card sync download: #{percent}%")
    end
  end

  defp sync_progress(:importing, count) when rem(count, 5000) == 0 do
    Logger.debug("Card sync import: #{count} cards")
  end

  defp sync_progress(_stage, _data), do: :ok
end
