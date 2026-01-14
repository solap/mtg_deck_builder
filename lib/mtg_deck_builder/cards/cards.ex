defmodule MtgDeckBuilder.Cards do
  @moduledoc """
  Context module for card operations.
  Provides search, lookup, and counting functionality for MTG cards.
  """

  import Ecto.Query
  alias MtgDeckBuilder.Cards.Card
  alias MtgDeckBuilder.Repo

  @doc """
  Search for cards by name with optional format filtering.

  Uses PostgreSQL trigram similarity for fuzzy matching.
  Returns up to `limit` results (default 50).

  ## Options

    * `:format` - Filter to cards legal in this format (e.g., :modern, :standard)
    * `:limit` - Maximum number of results (default 50)

  ## Examples

      iex> Cards.search("lightning bolt")
      [%Card{name: "Lightning Bolt", ...}]

      iex> Cards.search("bolt", format: :standard)
      [%Card{name: "Shock", ...}]

  """
  def search(query, opts \\ []) when is_binary(query) do
    format = Keyword.get(opts, :format)
    limit = Keyword.get(opts, :limit, 50)

    base_query =
      from c in Card,
        where: ilike(c.name, ^"%#{query}%"),
        order_by: [
          asc: fragment("length(?)", c.name),
          asc: c.name
        ],
        limit: ^limit

    base_query
    |> maybe_filter_by_format(format)
    |> Repo.all()
  end

  defp maybe_filter_by_format(query, nil), do: query

  defp maybe_filter_by_format(query, format) when is_atom(format) do
    format_key = Atom.to_string(format)

    from c in query,
      where:
        fragment(
          "?->>? = ?",
          c.legalities,
          ^format_key,
          ^"legal"
        )
  end

  defp maybe_filter_by_format(query, format) when is_binary(format) do
    from c in query,
      where:
        fragment(
          "?->>? = ?",
          c.legalities,
          ^format,
          ^"legal"
        )
  end

  @doc """
  Get a card by its Scryfall ID.

  ## Examples

      iex> Cards.get_by_scryfall_id("abc123")
      %Card{scryfall_id: "abc123", ...}

      iex> Cards.get_by_scryfall_id("invalid")
      nil

  """
  def get_by_scryfall_id(scryfall_id) when is_binary(scryfall_id) do
    Repo.get_by(Card, scryfall_id: scryfall_id)
  end

  @doc """
  Get a card by its primary ID.
  """
  def get(id) when is_binary(id) do
    Repo.get(Card, id)
  end

  @doc """
  Count the total number of cards in the database.

  Useful for verifying import success.

  ## Examples

      iex> Cards.count()
      27432

  """
  def count do
    Repo.aggregate(Card, :count)
  end

  @doc """
  Insert a card or update if it already exists (by scryfall_id).
  """
  def upsert(attrs) when is_map(attrs) do
    %Card{}
    |> Card.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :scryfall_id
    )
  end

  @doc """
  Batch insert multiple cards.
  Uses INSERT ... ON CONFLICT for efficient upserts.
  """
  def insert_all(cards_attrs) when is_list(cards_attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(cards_attrs, fn attrs ->
        attrs
        |> Map.put(:id, Ecto.UUID.generate())
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Card, entries,
      on_conflict: {:replace_all_except, [:id, :inserted_at]},
      conflict_target: :scryfall_id
    )
  end
end
