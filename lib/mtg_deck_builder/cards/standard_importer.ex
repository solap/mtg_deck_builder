defmodule MtgDeckBuilder.Cards.StandardImporter do
  @moduledoc """
  Imports Standard-legal cards from Scryfall API.
  Much smaller dataset than bulk import (~2000 cards vs 30000+).
  """

  require Logger

  alias MtgDeckBuilder.Cards
  alias MtgDeckBuilder.Cards.BulkImporter

  @scryfall_api "https://api.scryfall.com"
  @batch_size 50

  @doc """
  Imports all Standard-legal cards from Scryfall.
  Returns {:ok, count} or {:error, reason}.
  """
  def import_standard do
    Logger.info("Starting Standard cards import from Scryfall API...")

    case fetch_all_standard_cards() do
      {:ok, cards} ->
        count = insert_cards(cards)
        Logger.info("Standard import complete: #{count} cards inserted")
        {:ok, count}

      {:error, reason} ->
        Logger.error("Standard import failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_all_standard_cards do
    # Search for all Standard-legal cards
    url = "#{@scryfall_api}/cards/search?q=legal%3Astandard&unique=cards"
    fetch_paginated(url, [])
  end

  defp fetch_paginated(url, acc) do
    # Be nice to Scryfall API
    Process.sleep(100)

    case Tesla.get(url) do
      {:ok, %{status: 200, body: body}} ->
        data = Jason.decode!(body)
        cards = data["data"] || []
        new_acc = acc ++ cards

        Logger.info("Fetched #{length(new_acc)} Standard cards so far...")

        if data["has_more"] do
          fetch_paginated(data["next_page"], new_acc)
        else
          {:ok, new_acc}
        end

      {:ok, %{status: status, body: body}} ->
        {:error, "Scryfall API error: #{status} - #{body}"}

      {:error, reason} ->
        {:error, "HTTP error: #{inspect(reason)}"}
    end
  end

  defp insert_cards(cards) do
    cards
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce(0, fn batch, count ->
      attrs = Enum.map(batch, &BulkImporter.transform_card/1)
      Cards.insert_all(attrs)

      # Force GC to keep memory low
      :erlang.garbage_collect()

      count + length(batch)
    end)
  end
end
