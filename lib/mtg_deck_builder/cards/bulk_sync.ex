defmodule MtgDeckBuilder.Cards.BulkSync do
  @moduledoc """
  Handles incremental synchronization of card data from Scryfall bulk data.
  Only updates cards that have changed, and detects legality changes.
  """

  require Logger

  alias MtgDeckBuilder.Cards
  alias MtgDeckBuilder.Cards.{BulkImporter, Card}
  alias MtgDeckBuilder.Repo

  import Ecto.Query

  @batch_size 100

  @doc """
  Performs a full sync from Scryfall bulk data.
  Downloads fresh data, compares with existing DB, and updates only changed cards.

  Returns `{:ok, stats}` or `{:error, reason}`.
  """
  def sync(progress_callback \\ &default_progress/2) do
    with {:ok, url} <- BulkImporter.get_bulk_data_url(),
         _ <- progress_callback.(:downloading, 0),
         {:ok, file_path} <- BulkImporter.download_bulk_file(url, fn bytes, total ->
           progress_callback.(:downloading, {bytes, total})
         end),
         _ <- progress_callback.(:parsing, 0),
         {:ok, stats} <- diff_and_update(file_path, progress_callback) do
      # Clean up temp file
      File.rm(file_path)
      {:ok, stats}
    end
  end

  @doc """
  Compares bulk data file with existing database and updates changed cards.
  Returns stats about what was changed.
  Uses streaming JSON parsing to avoid memory issues with large files.
  """
  def diff_and_update(file_path, progress_callback \\ &default_progress/2) do
    Logger.info("Comparing bulk data with existing database...")

    # Load existing cards into a map for fast lookup
    existing_cards = load_existing_cards()
    progress_callback.(:syncing, 0)

    # Stream and process the bulk file using Jaxon
    stream_and_process(file_path, existing_cards, progress_callback)
  rescue
    e ->
      {:error, "Sync failed: #{Exception.message(e)}"}
  end

  defp stream_and_process(file_path, existing_cards, progress_callback) do
    initial_stats = %{
      total: 0,
      processed: 0,
      inserted: 0,
      updated: 0,
      unchanged: 0,
      legality_changes: []
    }

    # For initial sync (no existing cards), use fast bulk insert path
    is_initial_sync = map_size(existing_cards) == 0

    # Stream JSON array elements one by one
    final_stats =
      file_path
      |> File.stream!([], 65_536)
      |> Jaxon.Stream.from_enumerable()
      |> Jaxon.Stream.query([:root, :all])
      |> Stream.chunk_every(@batch_size)
      |> Enum.reduce(initial_stats, fn batch, stats ->
        batch_result = if is_initial_sync do
          process_batch_initial(batch)
        else
          process_batch(batch, existing_cards)
        end

        new_stats = %{
          stats |
          processed: stats.processed + length(batch),
          inserted: stats.inserted + batch_result.inserted,
          updated: stats.updated + batch_result.updated,
          unchanged: stats.unchanged + batch_result.unchanged,
          legality_changes: stats.legality_changes ++ batch_result.legality_changes
        }

        # Log progress every 1000 cards
        if rem(new_stats.processed, 1000) == 0 do
          Logger.info("Sync progress: #{new_stats.processed} cards processed")
        end

        progress_callback.(:syncing, new_stats.processed)

        # Force garbage collection after each batch to keep memory low
        :erlang.garbage_collect()

        new_stats
      end)

    {:ok, final_stats}
  end

  # Fast path for initial sync - no need to check existing cards
  defp process_batch_initial(batch) do
    cards_attrs = Enum.map(batch, fn scryfall_card ->
      BulkImporter.transform_card(scryfall_card)
    end)

    Cards.insert_all(cards_attrs)

    %{
      inserted: length(cards_attrs),
      updated: 0,
      unchanged: 0,
      legality_changes: []
    }
  end

  defp load_existing_cards do
    Card
    |> select([c], {c.scryfall_id, %{
      legalities: c.legalities,
      prices: c.prices,
      name: c.name,
      oracle_text: c.oracle_text,
      type_line: c.type_line,
      mana_cost: c.mana_cost,
      cmc: c.cmc,
      colors: c.colors,
      color_identity: c.color_identity,
      rarity: c.rarity,
      set_code: c.set_code
    }})
    |> Repo.all()
    |> Map.new()
  end

  defp process_batch(batch, existing_cards) do
    # Categorize cards in this batch
    {to_insert, to_update, unchanged, legality_changes} =
      Enum.reduce(batch, {[], [], 0, []}, fn scryfall_card, {ins, upd, unch, leg} ->
        scryfall_id = scryfall_card["id"]
        new_attrs = BulkImporter.transform_card(scryfall_card)

        case Map.get(existing_cards, scryfall_id) do
          nil ->
            # New card - add to insert list
            {[new_attrs | ins], upd, unch, leg}

          existing ->
            # Check if card has changed
            legality_change = detect_legality_change(existing, new_attrs)

            if card_changed?(existing, new_attrs) do
              changes = if legality_change, do: [legality_change | leg], else: leg
              {ins, [new_attrs | upd], unch, changes}
            else
              {ins, upd, unch + 1, leg}
            end
        end
      end)

    # Batch insert/update all cards at once
    all_cards = to_insert ++ to_update
    if length(all_cards) > 0 do
      Cards.insert_all(all_cards)
    end

    %{
      inserted: length(to_insert),
      updated: length(to_update),
      unchanged: unchanged,
      legality_changes: legality_changes
    }
  end

  defp card_changed?(existing, new_attrs) do
    existing.legalities != new_attrs.legalities ||
      existing.prices != new_attrs.prices ||
      existing.oracle_text != new_attrs.oracle_text ||
      existing.type_line != new_attrs.type_line ||
      existing.mana_cost != new_attrs.mana_cost
  end

  @doc """
  Detects if a card's legality has changed between existing and new data.
  Returns a change record or nil.
  """
  def detect_legality_change(existing, new_attrs) do
    old_legalities = existing.legalities || %{}
    new_legalities = new_attrs.legalities || %{}

    changes =
      Enum.reduce(new_legalities, [], fn {format, new_status}, acc ->
        old_status = Map.get(old_legalities, format)

        if old_status != new_status and old_status != nil do
          [{format, old_status, new_status} | acc]
        else
          acc
        end
      end)

    if Enum.empty?(changes) do
      nil
    else
      %{
        name: new_attrs.name,
        scryfall_id: new_attrs.scryfall_id,
        changes: changes
      }
    end
  end

  @doc """
  Detects legality changes between two sets of card data.
  Returns a list of cards with changed legalities.
  """
  def detect_legality_changes(old_cards, new_cards) when is_list(old_cards) and is_list(new_cards) do
    old_map = Map.new(old_cards, fn c -> {c.scryfall_id, c} end)

    Enum.reduce(new_cards, [], fn new_card, acc ->
      case Map.get(old_map, new_card.scryfall_id) do
        nil -> acc
        old_card ->
          case detect_legality_change(old_card, new_card) do
            nil -> acc
            change -> [change | acc]
          end
      end
    end)
  end

  defp default_progress(_stage, _data), do: :ok
end
