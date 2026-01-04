defmodule MtgDeckBuilder.Chat.CardResolver do
  @moduledoc """
  Resolves card names from user input to actual Card entities.

  Uses PostgreSQL pg_trgm extension for fuzzy matching to handle
  typos and partial names.
  """

  import Ecto.Query
  alias MtgDeckBuilder.Repo
  alias MtgDeckBuilder.Cards.Card

  @ets_table :recent_card_selections
  @high_similarity_threshold 0.8
  @suggestion_threshold 0.3
  @max_suggestions 5
  @max_recent 20
  @recent_ttl_ms 3_600_000  # 1 hour

  @doc """
  Initializes the ETS table for recent card selections.
  Should be called during application startup.
  """
  @spec init() :: :ok
  def init do
    if :ets.info(@ets_table) == :undefined do
      :ets.new(@ets_table, [:set, :public, :named_table])
    end
    :ok
  end

  @doc """
  Resolves a card name to a Card entity.

  ## Returns
    - {:ok, card} - Exact or high-confidence match found
    - {:ambiguous, cards} - Multiple possible matches, user should select
    - {:not_found, suggestions} - No good match, suggestions provided

  ## Parameters
    - name: The card name from user input
    - format: The deck format for legality filtering (atom like :modern)
    - opts: Optional keyword list with:
      - deck_card_ids: List of scryfall_ids of cards in deck (prefer these)
  """
  @spec resolve(String.t(), atom(), keyword()) :: {:ok, Card.t()} | {:ambiguous, [Card.t()]} | {:not_found, [String.t()]}
  def resolve(name, format, opts \\ []) when is_binary(name) do
    name = String.trim(name)
    deck_card_ids = Keyword.get(opts, :deck_card_ids, [])

    # First check recent selections
    case get_recent(name) do
      {:ok, card} -> {:ok, card}
      :not_found -> resolve_from_db(name, format, deck_card_ids)
    end
  end

  defp resolve_from_db(name, format, deck_card_ids) do
    # Query with trigram similarity
    query = from c in Card,
      where: fragment("similarity(?, ?) > ?", c.name, ^name, @suggestion_threshold),
      order_by: [desc: fragment("similarity(?, ?)", c.name, ^name)],
      limit: @max_suggestions

    cards = Repo.all(query)

    # First check for exact/high-confidence match in ALL cards (before format filtering)
    # This lets the executor show a proper "not legal in format" error
    exact_match = Enum.find(cards, fn card ->
      calculate_similarity(card.name, name) >= @high_similarity_threshold
    end)

    if exact_match do
      # Return the exact match - let executor handle format legality
      {:ok, exact_match}
    else
      # No exact match, filter by format and look for best match
      legal_cards = filter_by_format(cards, format)

      case legal_cards do
        [] ->
          # Check if any card in deck matches
          deck_match = Enum.find(cards, fn card ->
            card.scryfall_id in deck_card_ids
          end)

          if deck_match do
            {:ok, deck_match}
          else
            # Return suggestions
            suggestions = Enum.map(cards, & &1.name) |> Enum.take(@max_suggestions)
            {:not_found, suggestions}
          end

        [card] ->
          # Single legal match
          {:ok, card}

        [_first | _rest] = matches ->
          # Multiple legal matches - prefer deck cards
          deck_match = Enum.find(matches, fn card ->
            card.scryfall_id in deck_card_ids
          end)

          if deck_match do
            {:ok, deck_match}
          else
            {:ambiguous, matches}
          end
      end
    end
  end

  @doc """
  Returns suggestions for similar card names.
  """
  @spec suggest(String.t(), atom()) :: [String.t()]
  def suggest(name, format) do
    query = from c in Card,
      where: fragment("similarity(?, ?) > ?", c.name, ^name, @suggestion_threshold),
      order_by: [desc: fragment("similarity(?, ?)", c.name, ^name)],
      limit: @max_suggestions,
      select: c.name

    Repo.all(query)
    |> filter_suggestions_by_format(format)
  end

  @doc """
  Remembers a card selection for faster future lookups.
  """
  @spec remember_selection(String.t(), Card.t()) :: :ok
  def remember_selection(input_text, %Card{} = card) do
    init()
    now = System.monotonic_time(:millisecond)
    :ets.insert(@ets_table, {String.downcase(input_text), card.scryfall_id, now})

    # Cleanup old entries
    cleanup_old_entries()

    :ok
  end

  @doc """
  Gets a recently selected card for the given input.
  """
  @spec get_recent(String.t()) :: {:ok, Card.t()} | :not_found
  def get_recent(input_text) do
    init()
    key = String.downcase(input_text)
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@ets_table, key) do
      [{^key, scryfall_id, timestamp}] when now - timestamp < @recent_ttl_ms ->
        case Repo.get_by(Card, scryfall_id: scryfall_id) do
          nil -> :not_found
          card -> {:ok, card}
        end

      _ ->
        :not_found
    end
  end

  # Private helpers

  defp filter_by_format(cards, format) do
    format_key = Atom.to_string(format)

    Enum.filter(cards, fn card ->
      legality = get_in(card.legalities, [format_key]) || get_in(card.legalities, [Access.key(format_key)])
      legality == "legal"
    end)
  end

  defp filter_suggestions_by_format(names, _format) do
    # For suggestions, we show all names (user might want to see what's not legal)
    names
  end

  defp calculate_similarity(name1, name2) do
    # Simple Jaro-Winkler-like similarity
    n1 = String.downcase(name1)
    n2 = String.downcase(name2)

    if n1 == n2 do
      1.0
    else
      # Check if one contains the other
      cond do
        String.contains?(n1, n2) -> 0.9
        String.contains?(n2, n1) -> 0.85
        String.starts_with?(n1, n2) -> 0.8
        String.starts_with?(n2, n1) -> 0.75
        true ->
          # Use character overlap as fallback
          chars1 = String.graphemes(n1) |> MapSet.new()
          chars2 = String.graphemes(n2) |> MapSet.new()
          intersection = MapSet.intersection(chars1, chars2) |> MapSet.size()
          union = MapSet.union(chars1, chars2) |> MapSet.size()
          intersection / max(union, 1)
      end
    end
  end

  defp cleanup_old_entries do
    now = System.monotonic_time(:millisecond)

    :ets.tab2list(@ets_table)
    |> Enum.filter(fn {_key, _id, timestamp} -> now - timestamp >= @recent_ttl_ms end)
    |> Enum.each(fn {key, _, _} -> :ets.delete(@ets_table, key) end)

    # Also enforce max entries
    entries = :ets.tab2list(@ets_table)

    if length(entries) > @max_recent do
      entries
      |> Enum.sort_by(fn {_, _, timestamp} -> timestamp end)
      |> Enum.take(length(entries) - @max_recent)
      |> Enum.each(fn {key, _, _} -> :ets.delete(@ets_table, key) end)
    end
  end
end
