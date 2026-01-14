defmodule Mix.Tasks.Cards.Sync do
  @moduledoc """
  Synchronizes card data from Scryfall bulk data, updating only changed cards.

  ## Usage

      mix cards.sync

  This task downloads the latest oracle-cards bulk data from Scryfall and
  compares it with the existing database. Only cards that have changed
  (legalities, prices, oracle text, etc.) are updated.

  This is much faster than a full import for regular syncs.

  ## Output

  The task reports:
  - Number of cards processed
  - Number of new cards inserted
  - Number of existing cards updated
  - Number of unchanged cards
  - Any legality changes detected (bans, unbans, etc.)
  """

  use Mix.Task

  alias MtgDeckBuilder.Cards.BulkSync

  @shortdoc "Sync cards from Scryfall bulk data (incremental update)"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    start_time = System.monotonic_time(:second)

    IO.puts("\n=== MTG Deck Builder Card Sync ===\n")

    case BulkSync.sync(&progress_callback/2) do
      {:ok, stats} ->
        elapsed = System.monotonic_time(:second) - start_time
        print_summary(stats, elapsed)

      {:error, reason} ->
        IO.puts("\nError: #{reason}\n")
        exit({:shutdown, 1})
    end
  end

  defp progress_callback(:downloading, 0) do
    IO.write("Downloading oracle-cards.json... ")
  end

  defp progress_callback(:downloading, {bytes, total}) when total > 0 do
    percent = round(bytes / total * 100)
    mb = Float.round(bytes / 1_000_000, 1)
    IO.write("\rDownloading oracle-cards.json... #{mb}MB (#{percent}%)   ")
  end

  defp progress_callback(:downloading, {bytes, 0}) do
    mb = Float.round(bytes / 1_000_000, 1)
    IO.write("\rDownloading oracle-cards.json... #{mb}MB   ")
  end

  defp progress_callback(:parsing, _) do
    IO.puts("\nParsing and comparing with database...")
  end

  defp progress_callback(:syncing, count) do
    IO.write("\rProcessed #{count} cards...   ")
  end

  defp print_summary(stats, elapsed) do
    IO.puts("\n")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("Sync Complete!")
    IO.puts("=" |> String.duplicate(50))
    IO.puts("")
    IO.puts("  Total cards processed: #{stats.total}")
    IO.puts("  New cards inserted:    #{stats.inserted}")
    IO.puts("  Cards updated:         #{stats.updated}")
    IO.puts("  Cards unchanged:       #{stats.unchanged}")
    IO.puts("  Time elapsed:          #{elapsed} seconds")
    IO.puts("")

    if stats.legality_changes != [] do
      IO.puts("Legality Changes Detected:")
      IO.puts("-" |> String.duplicate(50))

      Enum.each(stats.legality_changes, fn change ->
        IO.puts("  #{change.name}:")
        Enum.each(change.changes, fn {format, old_status, new_status} ->
          IO.puts("    #{format}: #{old_status} -> #{new_status}")
        end)
      end)

      IO.puts("")
    else
      IO.puts("No legality changes detected.")
      IO.puts("")
    end
  end
end
