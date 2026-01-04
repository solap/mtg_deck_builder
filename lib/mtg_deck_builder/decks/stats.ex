defmodule MtgDeckBuilder.Decks.Stats do
  @moduledoc """
  Calculates deck statistics including mana curve, color distribution, and type breakdown.
  """

  alias MtgDeckBuilder.Decks.Deck

  @doc """
  Calculates all statistics for a deck.
  Returns a map with all stats.
  """
  def calculate(%Deck{mainboard: mainboard}) do
    %{
      mana_curve: mana_curve(mainboard),
      color_distribution: color_distribution(mainboard),
      type_breakdown: type_breakdown(mainboard),
      average_mana_value: average_mana_value(mainboard),
      total_price: total_price(mainboard)
    }
  end

  @doc """
  Calculates the mana curve distribution.
  Returns a map of CMC to card count.
  """
  def mana_curve(cards) do
    base = %{0 => 0, 1 => 0, 2 => 0, 3 => 0, 4 => 0, 5 => 0, "6+" => 0}

    Enum.reduce(cards, base, fn card, acc ->
      # Skip lands for mana curve
      if is_land?(card) do
        acc
      else
        cmc = trunc(card.cmc || 0)

        key =
          if cmc >= 6 do
            "6+"
          else
            cmc
          end

        Map.update!(acc, key, &(&1 + card.quantity))
      end
    end)
  end

  @doc """
  Calculates the color distribution.
  Returns a map of color symbol to count.
  """
  def color_distribution(cards) do
    base = %{"W" => 0, "U" => 0, "B" => 0, "R" => 0, "G" => 0, "C" => 0}

    Enum.reduce(cards, base, fn card, acc ->
      colors = card.colors || []

      if Enum.empty?(colors) do
        # Colorless cards (but not lands)
        if not is_land?(card) do
          Map.update!(acc, "C", &(&1 + card.quantity))
        else
          acc
        end
      else
        Enum.reduce(colors, acc, fn color, inner_acc ->
          Map.update!(inner_acc, color, &(&1 + card.quantity))
        end)
      end
    end)
  end

  @doc """
  Calculates the type breakdown.
  Returns a map of card type to count.
  """
  def type_breakdown(cards) do
    base = %{
      creature: 0,
      instant: 0,
      sorcery: 0,
      artifact: 0,
      enchantment: 0,
      planeswalker: 0,
      land: 0,
      other: 0
    }

    Enum.reduce(cards, base, fn card, acc ->
      type = get_card_type(card.type_line)
      Map.update!(acc, type, &(&1 + card.quantity))
    end)
  end

  @doc """
  Calculates the average mana value of non-land cards.
  """
  def average_mana_value(cards) do
    non_lands = Enum.reject(cards, &is_land?/1)

    if Enum.empty?(non_lands) do
      0.0
    else
      total_cmc =
        Enum.reduce(non_lands, 0.0, fn card, acc ->
          acc + (card.cmc || 0) * card.quantity
        end)

      total_cards = Enum.reduce(non_lands, 0, fn card, acc -> acc + card.quantity end)

      Float.round(total_cmc / total_cards, 2)
    end
  end

  @doc """
  Calculates the total price of all cards.
  """
  def total_price(cards) do
    total =
      Enum.reduce(cards, 0.0, fn card, acc ->
        price =
          case card.price do
            nil -> 0.0
            "" -> 0.0
            p when is_binary(p) -> String.to_float(p)
            p when is_float(p) -> p
            _ -> 0.0
          end

        acc + price * card.quantity
      end)

    Float.round(total, 2)
  end

  # Private helpers

  defp is_land?(card) do
    type_line = card.type_line || ""
    String.contains?(String.downcase(type_line), "land")
  end

  defp get_card_type(nil), do: :other

  defp get_card_type(type_line) do
    type_lower = String.downcase(type_line)

    cond do
      String.contains?(type_lower, "creature") -> :creature
      String.contains?(type_lower, "instant") -> :instant
      String.contains?(type_lower, "sorcery") -> :sorcery
      String.contains?(type_lower, "planeswalker") -> :planeswalker
      String.contains?(type_lower, "artifact") -> :artifact
      String.contains?(type_lower, "enchantment") -> :enchantment
      String.contains?(type_lower, "land") -> :land
      true -> :other
    end
  end
end
