defmodule MtgDeckBuilder.Cards.CopyImporter do
  @moduledoc """
  High-performance card importer using PostgreSQL COPY protocol.

  COPY is 10-100x faster than INSERT because it:
  - Bypasses SQL parsing per row
  - Batches WAL writes
  - Minimizes round-trips

  Uses streaming to keep memory usage low even for large datasets.
  """

  require Logger

  alias MtgDeckBuilder.Repo
  alias MtgDeckBuilder.Cards.BulkImporter

  @copy_columns ~w(
    id scryfall_id oracle_id name mana_cost cmc type_line oracle_text
    colors color_identity legalities prices is_basic_land rarity set_code
    inserted_at updated_at
  )

  @doc """
  Imports all cards from Scryfall using COPY protocol.

  Options:
    - :clear_first - if true, truncates table before import (default: true)
    - :progress_callback - function called with progress updates

  Returns {:ok, count} or {:error, reason}.
  """
  def import(opts \\ []) do
    clear_first = Keyword.get(opts, :clear_first, true)
    progress_callback = Keyword.get(opts, :progress_callback, fn _, _ -> :ok end)

    with {:ok, url} <- BulkImporter.get_bulk_data_url(),
         {:ok, file_path} <- download_file(url, progress_callback),
         {:ok, count} <- copy_from_file(file_path, clear_first, progress_callback) do
      File.rm(file_path)
      {:ok, count}
    end
  end

  defp download_file(url, progress_callback) do
    progress_callback.(:downloading, 0)
    BulkImporter.download_bulk_file(url, fn bytes, total ->
      progress_callback.(:downloading, {bytes, total})
    end)
  end

  defp copy_from_file(file_path, clear_first, progress_callback) do
    Logger.info("Starting COPY import from #{file_path}")
    progress_callback.(:importing, 0)

    # Use a dedicated Postgrex connection (not from Ecto pool)
    # This avoids pool exhaustion and allows long-running COPY
    config =
      Repo.config()
      |> Keyword.put(:pool_size, 1)
      |> Keyword.delete(:pool)

    {:ok, conn} = Postgrex.start_link(config)

    try do
      result = do_copy_import(conn, file_path, clear_first, progress_callback)
      GenServer.stop(conn)
      result
    catch
      kind, reason ->
        GenServer.stop(conn)
        Logger.error("COPY import failed: #{inspect({kind, reason})}")
        {:error, "COPY import failed: #{Exception.format(kind, reason)}"}
    end
  end

  defp do_copy_import(conn, file_path, clear_first, progress_callback) do
    columns = Enum.join(@copy_columns, ", ")

    copy_sql = "COPY cards (#{columns}) FROM STDIN WITH (FORMAT csv, NULL '')"

    Postgrex.transaction(
      conn,
      fn conn ->
        # Optionally clear existing data
        if clear_first do
          Logger.info("Truncating cards table...")
          Postgrex.query!(conn, "TRUNCATE TABLE cards", [])
        end

        # Create the COPY stream
        copy_stream = Postgrex.stream(conn, copy_sql, [])

        # Stream JSON file, transform to CSV rows, and pipe to COPY
        csv_stream =
          file_path
          |> File.stream!([], 65_536)
          |> Jaxon.Stream.from_enumerable()
          |> Jaxon.Stream.query([:root, :all])
          |> Stream.with_index(1)
          |> Stream.map(fn {card, idx} ->
            if rem(idx, 5000) == 0 do
              Logger.info("COPY progress: #{idx} cards")
              progress_callback.(:importing, idx)
              :erlang.garbage_collect()
            end
            card_to_csv_row(card)
          end)

        # Pipe CSV data into the COPY stream
        Enum.into(csv_stream, copy_stream)

        # Count total cards after COPY completes
        %Postgrex.Result{rows: [[count]]} = Postgrex.query!(conn, "SELECT COUNT(*) FROM cards", [])
        count
      end,
      timeout: :infinity
    )
    |> case do
      {:ok, count} ->
        Logger.info("COPY import complete: #{count} cards imported")
        {:ok, count}

      {:error, reason} ->
        Logger.error("COPY transaction failed: #{inspect(reason)}")
        {:error, inspect(reason)}
    end
  end

  defp card_to_csv_row(scryfall_card) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_iso8601()

    [
      Ecto.UUID.generate(),                                    # id
      scryfall_card["id"],                                     # scryfall_id
      scryfall_card["oracle_id"],                              # oracle_id
      scryfall_card["name"],                                   # name
      scryfall_card["mana_cost"],                              # mana_cost
      to_string(scryfall_card["cmc"] || 0),                    # cmc
      scryfall_card["type_line"],                              # type_line
      scryfall_card["oracle_text"],                            # oracle_text
      encode_pg_array(scryfall_card["colors"]),                # colors
      encode_pg_array(scryfall_card["color_identity"]),        # color_identity
      encode_json(scryfall_card["legalities"]),                # legalities
      encode_json(extract_prices(scryfall_card["prices"])),    # prices
      to_string(is_basic_land?(scryfall_card)),                # is_basic_land
      scryfall_card["rarity"],                                 # rarity
      scryfall_card["set"],                                    # set_code
      now,                                                     # inserted_at
      now                                                      # updated_at
    ]
    |> Enum.map(&escape_csv_field/1)
    |> Enum.join(",")
    |> Kernel.<>("\n")
  end

  defp escape_csv_field(nil), do: ""
  defp escape_csv_field(value) when is_binary(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      "\"" <> String.replace(value, "\"", "\"\"") <> "\""
    else
      value
    end
  end
  defp escape_csv_field(value), do: to_string(value)

  # PostgreSQL array format for COPY
  defp encode_pg_array(nil), do: "{}"
  defp encode_pg_array([]), do: "{}"
  defp encode_pg_array(list) when is_list(list) do
    "{" <> Enum.join(list, ",") <> "}"
  end

  defp encode_json(nil), do: "{}"
  defp encode_json(map) when is_map(map), do: Jason.encode!(map)

  defp extract_prices(nil), do: %{}
  defp extract_prices(prices) when is_map(prices) do
    %{"usd" => prices["usd"], "usd_foil" => prices["usd_foil"]}
  end

  defp is_basic_land?(%{"type_line" => type_line}) when is_binary(type_line) do
    String.contains?(type_line, "Basic Land")
  end
  defp is_basic_land?(_), do: false
end
