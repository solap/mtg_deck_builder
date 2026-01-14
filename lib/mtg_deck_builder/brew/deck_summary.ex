defmodule MtgDeckBuilder.Brew.DeckSummary do
  @moduledoc """
  Aggregated deck statistics for AI context.

  Provides a token-efficient representation of deck state including:
  - Card counts by board and type
  - Mana curve
  - Color distribution
  - Key cards status from brew
  """

  alias MtgDeckBuilder.Decks.Deck
  alias MtgDeckBuilder.Brew

  @type t :: %__MODULE__{
          format: atom(),
          mainboard_count: non_neg_integer(),
          sideboard_count: non_neg_integer(),
          cards_by_type: map(),
          mana_curve: [non_neg_integer()],
          color_distribution: map(),
          avg_mana_value: float(),
          land_count: non_neg_integer(),
          missing_key_cards: [String.t()],
          legality_issues: [String.t()],
          card_names: [String.t()]
        }

  defstruct format: :modern,
            mainboard_count: 0,
            sideboard_count: 0,
            cards_by_type: %{},
            mana_curve: [0, 0, 0, 0, 0, 0, 0, 0],
            color_distribution: %{},
            avg_mana_value: 0.0,
            land_count: 0,
            missing_key_cards: [],
            legality_issues: [],
            card_names: []

  @doc """
  Builds a DeckSummary from a Deck struct and optional Brew.

  ## Examples

      iex> DeckSummary.build(deck, brew)
      %DeckSummary{mainboard_count: 60, ...}
  """
  @spec build(Deck.t(), Brew.t() | nil) :: t()
  def build(%Deck{} = deck, brew \\ nil) do
    mainboard = deck.mainboard || []
    sideboard = deck.sideboard || []

    card_names = get_card_names(deck)

    %__MODULE__{
      format: deck.format,
      mainboard_count: count_cards(mainboard),
      sideboard_count: count_cards(sideboard),
      cards_by_type: build_type_breakdown(mainboard),
      mana_curve: build_mana_curve(mainboard),
      color_distribution: build_color_distribution(mainboard),
      avg_mana_value: calculate_avg_mana_value(mainboard),
      land_count: count_lands(mainboard),
      missing_key_cards: calculate_missing_key_cards(brew, card_names),
      legality_issues: [],
      card_names: card_names
    }
  end

  @doc """
  Gets a list of all card names in the deck (mainboard + sideboard).
  """
  @spec get_card_names(Deck.t()) :: [String.t()]
  def get_card_names(%Deck{} = deck) do
    mainboard_names = Enum.map(deck.mainboard || [], & &1.name)
    sideboard_names = Enum.map(deck.sideboard || [], & &1.name)
    Enum.uniq(mainboard_names ++ sideboard_names)
  end

  # Private functions

  defp count_cards(cards) do
    Enum.reduce(cards, 0, fn card, acc -> acc + (card.quantity || 1) end)
  end

  defp build_type_breakdown(cards) do
    cards
    |> Enum.reduce(%{}, fn card, acc ->
      type = get_primary_type(card.type_line)
      qty = card.quantity || 1
      Map.update(acc, type, qty, &(&1 + qty))
    end)
  end

  defp get_primary_type(nil), do: "Other"
  defp get_primary_type(type_line) do
    type_lower = String.downcase(type_line)

    cond do
      String.contains?(type_lower, "creature") -> "Creature"
      String.contains?(type_lower, "planeswalker") -> "Planeswalker"
      String.contains?(type_lower, "instant") -> "Instant"
      String.contains?(type_lower, "sorcery") -> "Sorcery"
      String.contains?(type_lower, "artifact") -> "Artifact"
      String.contains?(type_lower, "enchantment") -> "Enchantment"
      String.contains?(type_lower, "land") -> "Land"
      true -> "Other"
    end
  end

  defp build_mana_curve(cards) do
    # Initialize curve for CMC 0-7+
    initial = List.duplicate(0, 8)

    cards
    |> Enum.reject(&land?/1)
    |> Enum.reduce(initial, fn card, curve ->
      cmc = trunc(card.cmc || 0)
      idx = min(cmc, 7)
      qty = card.quantity || 1
      List.update_at(curve, idx, &(&1 + qty))
    end)
  end

  defp build_color_distribution(cards) do
    initial = %{"W" => 0, "U" => 0, "B" => 0, "R" => 0, "G" => 0, "C" => 0}

    cards
    |> Enum.reduce(initial, fn card, dist ->
      colors = card.colors || []
      qty = card.quantity || 1

      if Enum.empty?(colors) do
        # Colorless card
        Map.update!(dist, "C", &(&1 + qty))
      else
        Enum.reduce(colors, dist, fn color, d ->
          Map.update(d, color, qty, &(&1 + qty))
        end)
      end
    end)
  end

  defp calculate_avg_mana_value(cards) do
    non_lands = Enum.reject(cards, &land?/1)

    if Enum.empty?(non_lands) do
      0.0
    else
      total_cmc =
        Enum.reduce(non_lands, 0, fn card, acc ->
          acc + (card.cmc || 0) * (card.quantity || 1)
        end)

      total_cards = Enum.reduce(non_lands, 0, fn card, acc -> acc + (card.quantity || 1) end)

      Float.round(total_cmc / total_cards, 2)
    end
  end

  defp count_lands(cards) do
    cards
    |> Enum.filter(&land?/1)
    |> Enum.reduce(0, fn card, acc -> acc + (card.quantity || 1) end)
  end

  defp land?(card) do
    type_line = card.type_line || ""
    String.contains?(String.downcase(type_line), "land")
  end

  defp calculate_missing_key_cards(nil, _card_names), do: []
  defp calculate_missing_key_cards(%Brew{} = brew, card_names) do
    Brew.missing_key_cards(brew, card_names)
  end
end
