defmodule Mix.Tasks.Cards.Import do
  @moduledoc """
  Imports all cards from Scryfall bulk data into the local database.

  ## Usage

      mix cards.import

  This task downloads the oracle-cards bulk data file (~25MB) from Scryfall
  and imports all ~27,000 unique cards into the PostgreSQL database.

  The import process:
  1. Fetches the bulk data URL from Scryfall API
  2. Downloads the JSON file (~25MB)
  3. Parses and inserts cards in batches of 1000
  4. Cleans up the temporary file

  Expected runtime: 2-3 minutes depending on connection speed.
  """

  use Mix.Task

  alias MtgDeckBuilder.Cards.BulkImporter

  @shortdoc "Import cards from Scryfall bulk data"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    start_time = System.monotonic_time(:second)

    IO.puts("\n=== MTG Deck Builder Card Import ===\n")

    case BulkImporter.import(&progress_callback/2) do
      {:ok, count} ->
        elapsed = System.monotonic_time(:second) - start_time
        IO.puts("\n\nImported #{count} cards in #{elapsed} seconds.\n")

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

  defp progress_callback(:importing, 0) do
    IO.puts("\nParsing and importing cards...")
  end

  defp progress_callback(:importing, count) do
    IO.write("\rImported #{count} cards...   ")
  end
end
