defmodule MtgDeckBuilder.Chat.CommandExecutor do
  @moduledoc """
  Executes parsed commands against the deck state.
  """

  alias MtgDeckBuilder.AI.ParsedCommand
  alias MtgDeckBuilder.Cards.Card
  alias MtgDeckBuilder.Decks
  alias MtgDeckBuilder.Decks.{Deck, Validator}
  alias MtgDeckBuilder.Chat.{CardResolver, ResponseFormatter}

  @max_copies 4
  @max_sideboard 15

  @type result :: {:ok, Deck.t(), String.t()} | {:error, String.t()} | {:disambiguation, [Card.t()]}

  @doc """
  Executes a parsed command against the deck.

  Returns:
    - {:ok, updated_deck, message} - Success
    - {:error, message} - Failure
    - {:disambiguation, cards} - Multiple card matches, user must select
  """
  @spec execute(ParsedCommand.t(), Deck.t()) :: result()
  def execute(%ParsedCommand{action: action} = cmd, %Deck{} = deck) do
    case action do
      :add -> execute_add(cmd, deck)
      :remove -> execute_remove(cmd, deck)
      :set -> execute_set(cmd, deck)
      :move -> execute_move(cmd, deck)
      :query -> execute_query(cmd, deck)
      :undo -> execute_undo(cmd, deck)
      :help -> execute_help(cmd, deck)
    end
  end

  @doc """
  Executes an add command.
  """
  @spec execute_add(ParsedCommand.t(), Deck.t()) :: result()
  def execute_add(%ParsedCommand{card_name: name, quantity: qty, target_board: board}, deck) do
    format = deck.format || :modern

    case CardResolver.resolve(name, format) do
      {:ok, card} ->
        do_add(deck, card, board, qty, format)

      {:ambiguous, cards} ->
        {:disambiguation, cards}

      {:not_found, suggestions} ->
        msg = ResponseFormatter.format_error(:not_found, %{name: name, suggestions: suggestions})
        {:error, msg}
    end
  end

  defp do_add(deck, card, board, qty, format) do
    # Check format legality
    case check_format_legality(card, format) do
      :ok ->
        # Check copy limits
        case check_copy_limit(deck, card, qty) do
          :ok ->
            # Check sideboard limit
            case check_sideboard_limit(deck, board, qty) do
              :ok ->
                case Decks.add_card(deck, card.scryfall_id, board, qty) do
                  {:ok, updated_deck} ->
                    msg = ResponseFormatter.format_success(:add, %{card: card, quantity: qty, board: board})
                    CardResolver.remember_selection(card.name, card)
                    {:ok, updated_deck, msg}

                  {:error, reason} ->
                    {:error, reason}
                end

              {:error, _} = error ->
                error
            end

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Executes a remove command.
  """
  @spec execute_remove(ParsedCommand.t(), Deck.t()) :: result()
  def execute_remove(%ParsedCommand{card_name: name, quantity: qty, source_board: board}, deck) do
    board = board || :mainboard
    format = deck.format || :modern

    case CardResolver.resolve(name, format) do
      {:ok, card} ->
        do_remove(deck, card, board, qty)

      {:ambiguous, cards} ->
        {:disambiguation, cards}

      {:not_found, suggestions} ->
        msg = ResponseFormatter.format_error(:not_found, %{name: name, suggestions: suggestions})
        {:error, msg}
    end
  end

  defp do_remove(deck, card, board, qty) do
    board_list = Map.get(deck, board, [])

    case Enum.find(board_list, fn c -> c.scryfall_id == card.scryfall_id end) do
      nil ->
        msg = ResponseFormatter.format_error(:card_not_in_deck, %{name: card.name, board: board})
        {:error, msg}

      existing ->
        # If qty is nil or >= existing quantity, remove all
        remove_qty = if is_nil(qty) or qty >= existing.quantity, do: existing.quantity, else: qty

        if remove_qty >= existing.quantity do
          # Remove entirely
          updated_deck = Decks.remove_card(deck, card.scryfall_id, board)
          msg = ResponseFormatter.format_success(:remove, %{card: card, quantity: remove_qty, board: board})
          {:ok, updated_deck, msg}
        else
          # Decrease quantity
          case Decks.update_quantity(deck, card.scryfall_id, board, -remove_qty) do
            {:ok, updated_deck} ->
              msg = ResponseFormatter.format_success(:remove, %{card: card, quantity: remove_qty, board: board})
              {:ok, updated_deck, msg}

            {:error, reason} ->
              {:error, reason}
          end
        end
    end
  end

  @doc """
  Executes a set quantity command.
  """
  @spec execute_set(ParsedCommand.t(), Deck.t()) :: result()
  def execute_set(%ParsedCommand{card_name: name, quantity: qty}, deck) do
    format = deck.format || :modern

    case CardResolver.resolve(name, format) do
      {:ok, card} ->
        do_set(deck, card, qty)

      {:ambiguous, cards} ->
        {:disambiguation, cards}

      {:not_found, suggestions} ->
        msg = ResponseFormatter.format_error(:not_found, %{name: name, suggestions: suggestions})
        {:error, msg}
    end
  end

  defp do_set(deck, card, target_qty) do
    # Find the card in either board
    {current_board, current_qty} = find_card_in_deck(deck, card.scryfall_id)

    if is_nil(current_board) do
      # Card not in deck, treat as add
      case Decks.add_card(deck, card.scryfall_id, :mainboard, target_qty) do
        {:ok, updated_deck} ->
          msg = ResponseFormatter.format_success(:set, %{card: card, quantity: target_qty})
          {:ok, updated_deck, msg}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # Card exists, adjust quantity
      delta = target_qty - current_qty

      if delta == 0 do
        msg = "#{card.name} is already at #{target_qty} copies"
        {:ok, deck, msg}
      else
        case Decks.update_quantity(deck, card.scryfall_id, current_board, delta) do
          {:ok, updated_deck} ->
            msg = ResponseFormatter.format_success(:set, %{card: card, quantity: target_qty})
            {:ok, updated_deck, msg}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Executes a move command.
  """
  @spec execute_move(ParsedCommand.t(), Deck.t()) :: result()
  def execute_move(%ParsedCommand{card_name: name, quantity: qty, source_board: from, target_board: to}, deck) do
    format = deck.format || :modern
    from = from || :mainboard

    case CardResolver.resolve(name, format) do
      {:ok, card} ->
        do_move(deck, card, from, to, qty)

      {:ambiguous, cards} ->
        {:disambiguation, cards}

      {:not_found, suggestions} ->
        msg = ResponseFormatter.format_error(:not_found, %{name: name, suggestions: suggestions})
        {:error, msg}
    end
  end

  defp do_move(deck, card, from, to, qty) do
    from_list = Map.get(deck, from, [])

    case Enum.find(from_list, fn c -> c.scryfall_id == card.scryfall_id end) do
      nil ->
        msg = ResponseFormatter.format_error(:card_not_in_deck, %{name: card.name, board: from})
        {:error, msg}

      existing ->
        move_qty = if is_nil(qty), do: existing.quantity, else: min(qty, existing.quantity)

        if move_qty == existing.quantity do
          # Move all - use Decks.move_card
          case Decks.move_card(deck, card.scryfall_id, from, to) do
            {:ok, updated_deck} ->
              msg = ResponseFormatter.format_success(:move, %{card: card, quantity: move_qty, from: from, to: to})
              {:ok, updated_deck, msg}

            {:error, reason} ->
              {:error, reason}
          end
        else
          # Partial move - remove from source, add to target
          with {:ok, deck1} <- Decks.update_quantity(deck, card.scryfall_id, from, -move_qty),
               {:ok, deck2} <- Decks.add_card(deck1, card.scryfall_id, to, move_qty) do
            msg = ResponseFormatter.format_success(:move, %{card: card, quantity: move_qty, from: from, to: to})
            {:ok, deck2, msg}
          else
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  @doc """
  Executes a query command.
  """
  @spec execute_query(ParsedCommand.t(), Deck.t()) :: result()
  def execute_query(%ParsedCommand{query_type: :count, card_name: name}, deck) do
    format = deck.format || :modern

    case CardResolver.resolve(name, format) do
      {:ok, card} ->
        {mb_qty, sb_qty} = get_card_quantities(deck, card.scryfall_id)
        msg = ResponseFormatter.format_query_result(:count, %{card_name: card.name, mainboard: mb_qty, sideboard: sb_qty})
        {:ok, deck, msg}

      {:ambiguous, cards} ->
        {:disambiguation, cards}

      {:not_found, _suggestions} ->
        msg = ResponseFormatter.format_query_result(:count, %{card_name: name, mainboard: 0, sideboard: 0})
        {:ok, deck, msg}
    end
  end

  def execute_query(%ParsedCommand{query_type: :list, target_board: board}, deck) do
    board = board || :mainboard
    board_list = Map.get(deck, board, [])
    cards = Enum.map(board_list, fn c -> {c.name, c.quantity} end)
    msg = ResponseFormatter.format_query_result(:list, %{board: board, cards: cards})
    {:ok, deck, msg}
  end

  def execute_query(%ParsedCommand{query_type: :status}, deck) do
    mb_count = Deck.mainboard_count(deck)
    sb_count = Deck.sideboard_count(deck)
    validation_result = Validator.validate_deck(deck)

    {valid, errors} = case validation_result do
      {:ok, _} -> {true, []}
      {:error, error_list} when is_list(error_list) -> {false, error_list}
      {:error, error} -> {false, [error]}
    end

    msg = ResponseFormatter.format_query_result(:status, %{
      mainboard: mb_count,
      sideboard: sb_count,
      valid: valid,
      errors: errors
    })
    {:ok, deck, msg}
  end

  @doc """
  Executes an undo command.
  Actual undo logic is handled by UndoServer - this just dispatches.
  """
  @spec execute_undo(ParsedCommand.t(), Deck.t()) :: result()
  def execute_undo(_cmd, deck) do
    # Undo is handled at the LiveView level with UndoServer
    # This returns a marker that the caller should handle
    {:undo_requested, deck}
  end

  @doc """
  Executes a help command.
  """
  @spec execute_help(ParsedCommand.t(), Deck.t()) :: result()
  def execute_help(_cmd, deck) do
    msg = ResponseFormatter.format_success(:help, %{})
    {:ok, deck, msg}
  end

  # Private helpers

  defp find_card_in_deck(deck, scryfall_id) do
    mainboard_card = Enum.find(deck.mainboard, fn c -> c.scryfall_id == scryfall_id end)
    sideboard_card = Enum.find(deck.sideboard, fn c -> c.scryfall_id == scryfall_id end)

    cond do
      mainboard_card -> {:mainboard, mainboard_card.quantity}
      sideboard_card -> {:sideboard, sideboard_card.quantity}
      true -> {nil, 0}
    end
  end

  defp get_card_quantities(deck, scryfall_id) do
    mb_card = Enum.find(deck.mainboard, fn c -> c.scryfall_id == scryfall_id end)
    sb_card = Enum.find(deck.sideboard, fn c -> c.scryfall_id == scryfall_id end)

    mb_qty = if mb_card, do: mb_card.quantity, else: 0
    sb_qty = if sb_card, do: sb_card.quantity, else: 0

    {mb_qty, sb_qty}
  end

  defp check_format_legality(card, format) do
    format_key = Atom.to_string(format)
    legality = get_in(card.legalities, [format_key]) || "not_legal"

    case legality do
      "legal" -> :ok
      "restricted" -> :ok  # Vintage restricted cards are allowed (1 copy enforced elsewhere)
      status ->
        msg = ResponseFormatter.format_error(:format_illegal, %{card: card, format: format, reason: status})
        {:error, msg}
    end
  end

  defp check_copy_limit(deck, card, qty) do
    if card.is_basic_land do
      :ok
    else
      current = Deck.card_count(deck, card.scryfall_id)

      # Check Vintage restricted
      format_key = Atom.to_string(deck.format || :modern)
      legality = get_in(card.legalities, [format_key]) || "legal"

      max = if legality == "restricted", do: 1, else: @max_copies

      if current + qty > max do
        if legality == "restricted" do
          msg = ResponseFormatter.format_error(:restricted_limit, %{card: card})
          {:error, msg}
        else
          msg = ResponseFormatter.format_error(:copy_limit, %{card: card, current: current, max: max})
          {:error, msg}
        end
      else
        :ok
      end
    end
  end

  defp check_sideboard_limit(deck, :sideboard, qty) do
    current = Deck.sideboard_count(deck)

    if current + qty > @max_sideboard do
      msg = ResponseFormatter.format_error(:sideboard_full, %{current: current})
      {:error, msg}
    else
      :ok
    end
  end

  defp check_sideboard_limit(_deck, _board, _qty), do: :ok
end
