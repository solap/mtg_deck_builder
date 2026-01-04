defmodule MtgDeckBuilder.Decks.Validator do
  @moduledoc """
  Validates decks against format rules and legality requirements.
  """

  alias MtgDeckBuilder.Cards
  alias MtgDeckBuilder.Decks.Deck

  @max_copies 4
  @max_sideboard 15
  @min_mainboard 60

  @doc """
  Checks if a card is legal in a given format.
  """
  def legal_in_format?(card, format) when is_atom(format) do
    format_key = Atom.to_string(format)
    legality = get_in(card.legalities, [format_key])
    legality == "legal"
  end

  def legal_in_format?(card, format) when is_binary(format) do
    legality = get_in(card.legalities, [format])
    legality == "legal"
  end

  @doc """
  Checks if a card is restricted in a format (Vintage only).
  """
  def restricted_in_format?(card, format) do
    format_key = if is_atom(format), do: Atom.to_string(format), else: format
    legality = get_in(card.legalities, [format_key])
    legality == "restricted"
  end

  @doc """
  Validates the entire deck, returning validation results.

  Returns `{:ok, deck}` if valid, or `{:error, errors}` with a list of validation errors.
  """
  def validate_deck(%Deck{} = deck) do
    errors =
      []
      |> check_mainboard_minimum(deck)
      |> check_sideboard_limit(deck)
      |> check_copy_limits(deck)
      |> check_restricted(deck)

    if Enum.empty?(errors) do
      {:ok, deck}
    else
      {:error, errors}
    end
  end

  @doc """
  Gets all validation errors for a deck.
  """
  def get_errors(%Deck{} = deck) do
    []
    |> check_mainboard_minimum(deck)
    |> check_sideboard_limit(deck)
    |> check_copy_limits(deck)
    |> check_restricted(deck)
    |> Enum.reverse()
  end

  @doc """
  Checks if the deck is valid (has no errors).
  """
  def valid?(%Deck{} = deck) do
    get_errors(deck) == []
  end

  defp check_mainboard_minimum(errors, %Deck{} = deck) do
    count = Deck.mainboard_count(deck)

    if count < @min_mainboard do
      ["Mainboard requires at least #{@min_mainboard} cards (currently #{count})" | errors]
    else
      errors
    end
  end

  defp check_sideboard_limit(errors, %Deck{} = deck) do
    count = Deck.sideboard_count(deck)

    if count > @max_sideboard do
      ["Sideboard cannot exceed #{@max_sideboard} cards (currently #{count})" | errors]
    else
      errors
    end
  end

  defp check_copy_limits(errors, %Deck{mainboard: mainboard, sideboard: sideboard}) do
    all_cards =
      (mainboard ++ sideboard)
      |> Enum.group_by(& &1.scryfall_id)

    Enum.reduce(all_cards, errors, fn {_id, cards}, acc ->
      card = hd(cards)
      total = Enum.sum(Enum.map(cards, & &1.quantity))

      if not card.is_basic_land and total > @max_copies do
        ["#{card.name}: maximum #{@max_copies} copies allowed (found #{total})" | acc]
      else
        acc
      end
    end)
  end

  defp check_restricted(errors, %Deck{format: format, mainboard: mainboard, sideboard: sideboard})
       when format == :vintage do
    # Get restricted cards from Scryfall data
    all_cards = mainboard ++ sideboard

    Enum.reduce(all_cards, errors, fn card, acc ->
      # Check if this card is restricted
      if card.quantity > 1 do
        # Need to look up full card data to check restriction
        case Cards.get_by_scryfall_id(card.scryfall_id) do
          nil ->
            acc

          full_card ->
            if restricted_in_format?(full_card, format) do
              ["#{card.name}: restricted in Vintage (maximum 1 copy)" | acc]
            else
              acc
            end
        end
      else
        acc
      end
    end)
  end

  defp check_restricted(errors, _deck), do: errors

  @doc """
  Identifies cards in the deck that are not legal in the given format.
  Returns a list of `{card, reason}` tuples.
  """
  def find_illegal_cards(%Deck{mainboard: mainboard, sideboard: sideboard}, format) do
    all_cards =
      Enum.map(mainboard, fn c -> {c, :mainboard} end) ++
        Enum.map(sideboard, fn c -> {c, :sideboard} end)

    Enum.reduce(all_cards, [], fn {deck_card, board}, acc ->
      case Cards.get_by_scryfall_id(deck_card.scryfall_id) do
        nil ->
          acc

        card ->
          format_key = Atom.to_string(format)
          legality = get_in(card.legalities, [format_key])

          case legality do
            "legal" ->
              acc

            "banned" ->
              [{deck_card, board, "banned"} | acc]

            "not_legal" ->
              [{deck_card, board, "not_legal"} | acc]

            "restricted" ->
              if deck_card.quantity > 1 do
                [{deck_card, board, "restricted"} | acc]
              else
                acc
              end

            _ ->
              [{deck_card, board, "not_legal"} | acc]
          end
      end
    end)
  end
end
