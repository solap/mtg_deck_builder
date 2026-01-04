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

  @batch_size 500

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
  """
  def diff_and_update(file_path, progress_callback \\ &default_progress/2) do
    Logger.info("Comparing bulk data with existing database...")

    # Load existing cards into a map for fast lookup
    existing_cards = load_existing_cards()
    progress_callback.(:syncing, 0)

    # Parse and process the bulk file
    file_path
    |> File.read!()
    |> Jason.decode!()
    |> process_cards_in_batches(existing_cards, progress_callback)
  rescue
    e ->
      {:error, "Sync failed: #{Exception.message(e)}"}
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

  defp process_cards_in_batches(cards, existing_cards, progress_callback) do
    total_cards = length(cards)

    initial_stats = %{
      total: total_cards,
      processed: 0,
      inserted: 0,
      updated: 0,
      unchanged: 0,
      legality_changes: []
    }

    final_stats =
      cards
      |> Enum.chunk_every(@batch_size)
      |> Enum.reduce(initial_stats, fn batch, stats ->
        batch_result = process_batch(batch, existing_cards)

        new_stats = %{
          stats |
          processed: stats.processed + length(batch),
          inserted: stats.inserted + batch_result.inserted,
          updated: stats.updated + batch_result.updated,
          unchanged: stats.unchanged + batch_result.unchanged,
          legality_changes: stats.legality_changes ++ batch_result.legality_changes
        }

        progress_callback.(:syncing, new_stats.processed)
        new_stats
      end)

    {:ok, final_stats}
  end

  defp process_batch(batch, existing_cards) do
    Enum.reduce(batch, %{inserted: 0, updated: 0, unchanged: 0, legality_changes: []}, fn scryfall_card, acc ->
      scryfall_id = scryfall_card["id"]
      new_attrs = BulkImporter.transform_card(scryfall_card)

      case Map.get(existing_cards, scryfall_id) do
        nil ->
          # New card - insert it
          case Cards.upsert(new_attrs) do
            {:ok, _} -> %{acc | inserted: acc.inserted + 1}
            {:error, _} -> acc
          end

        existing ->
          # Check if card has changed
          legality_change = detect_legality_change(existing, new_attrs)

          if card_changed?(existing, new_attrs) do
            case Cards.upsert(new_attrs) do
              {:ok, _} ->
                changes = if legality_change, do: [legality_change | acc.legality_changes], else: acc.legality_changes
                %{acc | updated: acc.updated + 1, legality_changes: changes}
              {:error, _} ->
                acc
            end
          else
            %{acc | unchanged: acc.unchanged + 1}
          end
      end
    end)
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
