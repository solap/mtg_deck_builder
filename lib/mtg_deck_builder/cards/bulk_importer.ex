defmodule MtgDeckBuilder.Cards.BulkImporter do
  @moduledoc """
  Imports card data from Scryfall bulk data files.
  Uses the oracle-cards bulk data file (~27k unique cards, ~25MB).
  """

  require Logger

  alias MtgDeckBuilder.Cards

  @scryfall_bulk_api "https://api.scryfall.com/bulk-data"
  @batch_size 1000

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, ""},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Timeout, timeout: 30_000}
    ], {Tesla.Adapter.Hackney, recv_timeout: 30_000})
  end

  @doc """
  Gets the download URL for the oracle-cards bulk data file from Scryfall.

  Returns `{:ok, url}` or `{:error, reason}`.
  """
  def get_bulk_data_url do
    case Tesla.get(client(), @scryfall_bulk_api) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        oracle_cards =
          Enum.find(body["data"], fn item ->
            item["type"] == "oracle_cards"
          end)

        case oracle_cards do
          nil -> {:error, "oracle_cards bulk data not found"}
          %{"download_uri" => url} -> {:ok, url}
        end

      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        data = Jason.decode!(body)

        oracle_cards =
          Enum.find(data["data"], fn item ->
            item["type"] == "oracle_cards"
          end)

        case oracle_cards do
          nil -> {:error, "oracle_cards bulk data not found"}
          %{"download_uri" => url} -> {:ok, url}
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Scryfall API returned status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Failed to connect to Scryfall: #{inspect(reason)}"}
    end
  end

  @doc """
  Downloads the bulk data file to a temporary location.

  Returns `{:ok, file_path}` or `{:error, reason}`.
  """
  def download_bulk_file(url, progress_callback \\ fn _bytes, _total -> :ok end) do
    temp_file = Path.join(System.tmp_dir!(), "scryfall_oracle_cards_#{:os.system_time(:second)}.json")

    Logger.info("Downloading bulk data from #{url}")

    case download_with_progress(url, temp_file, progress_callback) do
      :ok -> {:ok, temp_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp download_with_progress(url, dest_path, progress_callback) do
    # Use hackney directly for streaming download
    case :hackney.get(url, [], "", [follow_redirect: true, recv_timeout: 60_000]) do
      {:ok, 200, headers, client_ref} ->
        content_length =
          headers
          |> Enum.find(fn {k, _v} -> String.downcase(k) == "content-length" end)
          |> case do
            {_, length} -> String.to_integer(length)
            nil -> 0
          end

        file = File.open!(dest_path, [:write, :binary])

        result = stream_to_file(client_ref, file, 0, content_length, progress_callback)
        File.close(file)
        result

      {:ok, status, _headers, _ref} ->
        {:error, "Download failed with status #{status}"}

      {:error, reason} ->
        {:error, "Download failed: #{inspect(reason)}"}
    end
  end

  defp stream_to_file(client_ref, file, bytes_received, total, progress_callback) do
    case :hackney.stream_body(client_ref) do
      {:ok, data} ->
        IO.binwrite(file, data)
        new_bytes = bytes_received + byte_size(data)
        progress_callback.(new_bytes, total)
        stream_to_file(client_ref, file, new_bytes, total, progress_callback)

      :done ->
        :ok

      {:error, reason} ->
        {:error, "Stream error: #{inspect(reason)}"}
    end
  end

  @doc """
  Parses the bulk JSON file and inserts cards in batches.

  Returns `{:ok, count}` or `{:error, reason}`.
  """
  def parse_and_insert(file_path, progress_callback \\ fn _count -> :ok end) do
    Logger.info("Parsing and importing cards from #{file_path}")

    file_path
    |> File.read!()
    |> Jason.decode!()
    |> Enum.chunk_every(@batch_size)
    |> Enum.reduce({0, 0}, fn batch, {total_count, batch_num} ->
      cards_attrs = Enum.map(batch, &transform_card/1)
      {inserted, _} = Cards.insert_all(cards_attrs)
      new_count = total_count + inserted
      progress_callback.(new_count)
      {new_count, batch_num + 1}
    end)
    |> then(fn {count, _} -> {:ok, count} end)
  rescue
    e ->
      {:error, "Parse/insert failed: #{Exception.message(e)}"}
  end

  @doc """
  Transforms a Scryfall card JSON object into attributes for our Card schema.
  """
  def transform_card(scryfall_card) when is_map(scryfall_card) do
    %{
      scryfall_id: scryfall_card["id"],
      oracle_id: scryfall_card["oracle_id"],
      name: scryfall_card["name"],
      mana_cost: scryfall_card["mana_cost"],
      cmc: scryfall_card["cmc"],
      type_line: scryfall_card["type_line"],
      oracle_text: scryfall_card["oracle_text"],
      colors: scryfall_card["colors"] || [],
      color_identity: scryfall_card["color_identity"] || [],
      legalities: scryfall_card["legalities"] || %{},
      prices: extract_prices(scryfall_card["prices"]),
      is_basic_land: is_basic_land?(scryfall_card),
      rarity: scryfall_card["rarity"],
      set_code: scryfall_card["set"]
    }
  end

  defp extract_prices(nil), do: %{}

  defp extract_prices(prices) when is_map(prices) do
    %{
      "usd" => prices["usd"],
      "usd_foil" => prices["usd_foil"]
    }
  end

  defp is_basic_land?(%{"type_line" => type_line}) when is_binary(type_line) do
    String.contains?(type_line, "Basic Land")
  end

  defp is_basic_land?(_), do: false

  @doc """
  Main import function that handles the full download and import process.

  Returns `{:ok, count}` or `{:error, reason}`.
  """
  def import(progress_callback \\ &default_progress/2) do
    with {:ok, url} <- get_bulk_data_url(),
         _ <- progress_callback.(:downloading, 0),
         {:ok, file_path} <- download_bulk_file(url, fn bytes, total ->
           progress_callback.(:downloading, {bytes, total})
         end),
         _ <- progress_callback.(:importing, 0),
         {:ok, count} <- parse_and_insert(file_path, fn count ->
           progress_callback.(:importing, count)
         end) do
      # Clean up temp file
      File.rm(file_path)
      {:ok, count}
    end
  end

  defp default_progress(_stage, _data), do: :ok
end
