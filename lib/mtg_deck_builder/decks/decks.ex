defmodule MtgDeckBuilder.Decks do
  @moduledoc """
  Context module for deck operations.
  """

  alias MtgDeckBuilder.Cards
  alias MtgDeckBuilder.Decks.{Deck, DeckCard, RemovedCard, Validator}

  @max_copies 4
  @max_sideboard 15

  @doc """
  Adds a card to the specified board of a deck.

  Returns `{:ok, updated_deck}` or `{:error, reason}`.
  """
  def add_card(%Deck{} = deck, scryfall_id, board, quantity \\ 1)
      when board in [:mainboard, :sideboard] do
    with {:ok, card} <- get_card(scryfall_id),
         :ok <- validate_can_add(deck, card, board, quantity) do
      {:ok, do_add_card(deck, card, board, quantity)}
    end
  end

  defp get_card(scryfall_id) do
    case Cards.get_by_scryfall_id(scryfall_id) do
      nil -> {:error, "Card not found"}
      card -> {:ok, card}
    end
  end

  defp validate_can_add(deck, card, board, quantity) do
    cond do
      # Basic lands have no copy limit
      card.is_basic_land ->
        validate_sideboard_limit(deck, board, quantity)

      # Check 4-copy limit
      Deck.card_count(deck, card.scryfall_id) + quantity > @max_copies ->
        {:error, "Maximum #{@max_copies} copies allowed"}

      # Check sideboard limit
      board == :sideboard and Deck.sideboard_count(deck) + quantity > @max_sideboard ->
        {:error, "Sideboard cannot exceed #{@max_sideboard} cards"}

      true ->
        :ok
    end
  end

  defp validate_sideboard_limit(deck, :sideboard, quantity) do
    if Deck.sideboard_count(deck) + quantity > @max_sideboard do
      {:error, "Sideboard cannot exceed #{@max_sideboard} cards"}
    else
      :ok
    end
  end

  defp validate_sideboard_limit(_deck, _board, _quantity), do: :ok

  defp do_add_card(deck, card, board, quantity) do
    board_list = Map.get(deck, board)
    deck_card = DeckCard.from_card(card, quantity)

    updated_list =
      case Enum.find_index(board_list, fn c -> c.scryfall_id == card.scryfall_id end) do
        nil ->
          # Card not in list, add it
          [deck_card | board_list]

        index ->
          # Card exists, update quantity
          List.update_at(board_list, index, fn existing ->
            %{existing | quantity: existing.quantity + quantity}
          end)
      end
      |> Enum.sort_by(& &1.name)

    deck
    |> Map.put(board, updated_list)
    |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())
  end

  @doc """
  Removes a card from the specified board.
  """
  def remove_card(%Deck{} = deck, scryfall_id, board) when board in [:mainboard, :sideboard] do
    board_list = Map.get(deck, board)
    updated_list = Enum.reject(board_list, fn c -> c.scryfall_id == scryfall_id end)

    deck
    |> Map.put(board, updated_list)
    |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())
  end

  @doc """
  Updates the quantity of a card in the specified board.
  If quantity becomes 0 or negative, removes the card.
  """
  def update_quantity(%Deck{} = deck, scryfall_id, board, delta)
      when board in [:mainboard, :sideboard] do
    board_list = Map.get(deck, board)

    case Enum.find_index(board_list, fn c -> c.scryfall_id == scryfall_id end) do
      nil ->
        {:error, "Card not found in #{board}"}

      index ->
        card = Enum.at(board_list, index)
        new_quantity = card.quantity + delta

        cond do
          new_quantity <= 0 ->
            {:ok, remove_card(deck, scryfall_id, board)}

          not card.is_basic_land and
              Deck.card_count(deck, scryfall_id) - card.quantity + new_quantity > @max_copies ->
            {:error, "Maximum #{@max_copies} copies allowed"}

          board == :sideboard and
              Deck.sideboard_count(deck) - card.quantity + new_quantity > @max_sideboard ->
            {:error, "Sideboard cannot exceed #{@max_sideboard} cards"}

          true ->
            updated_list = List.update_at(board_list, index, fn c -> %{c | quantity: new_quantity} end)

            updated_deck =
              deck
              |> Map.put(board, updated_list)
              |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

            {:ok, updated_deck}
        end
    end
  end

  @doc """
  Moves a card from one board to another.
  """
  def move_card(%Deck{} = deck, scryfall_id, from, to)
      when from in [:mainboard, :sideboard, :staging] and to in [:mainboard, :sideboard, :staging] and from != to do
    from_field = board_to_field(from)
    to_field = board_to_field(to)
    from_list = Map.get(deck, from_field)

    case Enum.find(from_list, fn c -> c.scryfall_id == scryfall_id end) do
      nil ->
        {:error, "Card not found in #{from}"}

      card ->
        # Check sideboard limit if moving to sideboard
        if to == :sideboard and Deck.sideboard_count(deck) + card.quantity > @max_sideboard do
          {:error, "Sideboard cannot exceed #{@max_sideboard} cards"}
        else
          to_list = Map.get(deck, to_field)

          # Remove from source
          updated_from = Enum.reject(from_list, fn c -> c.scryfall_id == scryfall_id end)

          # Add to destination (merge if exists)
          updated_to =
            case Enum.find_index(to_list, fn c -> c.scryfall_id == scryfall_id end) do
              nil ->
                [card | to_list]

              index ->
                List.update_at(to_list, index, fn existing ->
                  %{existing | quantity: existing.quantity + card.quantity}
                end)
            end
            |> Enum.sort_by(& &1.name)

          updated_deck =
            deck
            |> Map.put(from_field, updated_from)
            |> Map.put(to_field, updated_to)
            |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

          {:ok, updated_deck}
        end
    end
  end

  # Map board names to deck struct fields
  defp board_to_field(:mainboard), do: :mainboard
  defp board_to_field(:sideboard), do: :sideboard
  defp board_to_field(:staging), do: :removed_cards

  @doc """
  Moves a card from mainboard/sideboard to the staging area.
  """
  def move_to_staging(%Deck{} = deck, scryfall_id, from_board, reason \\ "Staged for later")
      when from_board in [:mainboard, :sideboard] do
    from_list = Map.get(deck, from_board)

    case Enum.find(from_list, fn c -> c.scryfall_id == scryfall_id end) do
      nil ->
        {:error, "Card not found in #{from_board}"}

      card ->
        # Create a RemovedCard (staging card) from the deck card
        staged_card = RemovedCard.from_deck_card(card, reason, from_board)

        # Remove from source board
        updated_from = Enum.reject(from_list, fn c -> c.scryfall_id == scryfall_id end)

        # Add to staging area (check if already exists)
        updated_removed =
          case Enum.find_index(deck.removed_cards, fn c -> c.scryfall_id == scryfall_id end) do
            nil ->
              [staged_card | deck.removed_cards]

            index ->
              List.update_at(deck.removed_cards, index, fn existing ->
                %{existing | quantity: existing.quantity + card.quantity}
              end)
          end

        updated_deck =
          deck
          |> Map.put(from_board, updated_from)
          |> Map.put(:removed_cards, updated_removed)
          |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

        {:ok, updated_deck}
    end
  end

  @doc """
  Moves illegal cards to the removed_cards list when format changes.
  Returns `{updated_deck, count_moved}`.
  """
  def move_illegal_to_removed(%Deck{} = deck, new_format) do
    illegal_cards = Validator.find_illegal_cards(deck, new_format)

    if Enum.empty?(illegal_cards) do
      {%{deck | format: new_format}, 0}
    else
      # Create removed cards from illegal cards
      new_removed =
        Enum.map(illegal_cards, fn {card, board, reason} ->
          RemovedCard.from_deck_card(card, reason, board)
        end)

      # Get scryfall_ids to remove
      illegal_ids = Enum.map(illegal_cards, fn {card, _board, _reason} -> card.scryfall_id end)

      # Remove from mainboard and sideboard
      new_mainboard =
        Enum.reject(deck.mainboard, fn c -> c.scryfall_id in illegal_ids end)

      new_sideboard =
        Enum.reject(deck.sideboard, fn c -> c.scryfall_id in illegal_ids end)

      updated_deck = %{
        deck
        | format: new_format,
          mainboard: new_mainboard,
          sideboard: new_sideboard,
          removed_cards: deck.removed_cards ++ new_removed,
          updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      {updated_deck, length(illegal_cards)}
    end
  end

  @doc """
  Restores a card from the staging area to the specified board.
  Cards can be restored even if not legal in the current format (user can decide).
  """
  def restore_card(%Deck{} = deck, scryfall_id, to_board) when to_board in [:mainboard, :sideboard] do
    case Enum.find(deck.removed_cards, fn c -> c.scryfall_id == scryfall_id end) do
      nil ->
        {:error, "Card not found in staging area"}

      removed_card ->
        # Create DeckCard from staged card
        deck_card = %DeckCard{
          scryfall_id: removed_card.scryfall_id,
          name: removed_card.name,
          quantity: removed_card.quantity,
          mana_cost: removed_card.mana_cost,
          cmc: removed_card.cmc,
          type_line: removed_card.type_line,
          oracle_text: removed_card.oracle_text,
          colors: removed_card.colors,
          price: removed_card.price,
          is_basic_land: removed_card.is_basic_land
        }

        # Remove from staging area
        new_removed = Enum.reject(deck.removed_cards, fn c -> c.scryfall_id == scryfall_id end)

        # Add to target board (merge if exists)
        board_list = Map.get(deck, to_board)

        new_board_list =
          case Enum.find_index(board_list, fn c -> c.scryfall_id == scryfall_id end) do
            nil ->
              [deck_card | board_list]

            index ->
              List.update_at(board_list, index, fn existing ->
                %{existing | quantity: existing.quantity + deck_card.quantity}
              end)
          end
          |> Enum.sort_by(& &1.name)

        updated_deck =
          deck
          |> Map.put(:removed_cards, new_removed)
          |> Map.put(to_board, new_board_list)
          |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())

        {:ok, updated_deck}
    end
  end

  @doc """
  Removes a card from the staging area completely.
  """
  def remove_from_staging(%Deck{} = deck, scryfall_id) do
    new_removed = Enum.reject(deck.removed_cards, fn c -> c.scryfall_id == scryfall_id end)

    deck
    |> Map.put(:removed_cards, new_removed)
    |> Map.put(:updated_at, DateTime.utc_now() |> DateTime.to_iso8601())
  end
end
