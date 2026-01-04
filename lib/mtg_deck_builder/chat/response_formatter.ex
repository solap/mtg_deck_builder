defmodule MtgDeckBuilder.Chat.ResponseFormatter do
  @moduledoc """
  Formats command results into user-friendly messages.
  """

  alias MtgDeckBuilder.Cards.Card

  @doc """
  Formats a successful command result.
  """
  @spec format_success(atom(), map()) :: String.t()
  def format_success(:add, %{card: card, quantity: qty, board: board}) do
    "Added #{qty}x #{card.name} to #{board}"
  end

  def format_success(:remove, %{card: card, quantity: qty, board: board}) do
    "Removed #{qty}x #{card.name} from #{board}"
  end

  def format_success(:set, %{card: card, quantity: qty}) do
    "Updated #{card.name} to #{qty} copies"
  end

  def format_success(:move, %{card: card, quantity: qty, from: from, to: to}) do
    "Moved #{qty}x #{card.name} from #{from} to #{to}"
  end

  def format_success(:undo, %{description: desc}) do
    "Undone: #{desc}"
  end

  def format_success(:help, _) do
    """
    Available commands:
    • add [qty] <card> [to mainboard/sideboard]
    • remove [qty] <card> [from mainboard/sideboard]
    • set <card> to <qty>
    • move [qty] <card> to mainboard/sideboard
    • how many <card>
    • show mainboard/sideboard
    • deck status
    • undo
    • help
    """
  end

  def format_success(action, details) do
    "#{action}: #{inspect(details)}"
  end

  @doc """
  Formats a query result.
  """
  @spec format_query_result(atom(), map()) :: String.t()
  def format_query_result(:count, %{card_name: name, mainboard: mb, sideboard: sb}) do
    total = mb + sb
    parts = []
    parts = if mb > 0, do: parts ++ ["#{mb} in mainboard"], else: parts
    parts = if sb > 0, do: parts ++ ["#{sb} in sideboard"], else: parts

    if total == 0 do
      "#{name} is not in your deck"
    else
      "You have #{total}x #{name} (#{Enum.join(parts, ", ")})"
    end
  end

  def format_query_result(:list, %{board: board, cards: cards}) do
    if Enum.empty?(cards) do
      "#{board} is empty"
    else
      card_lines = Enum.map(cards, fn {name, qty} -> "• #{qty}x #{name}" end)
      total = Enum.reduce(cards, 0, fn {_, qty}, acc -> acc + qty end)

      """
      #{String.capitalize(to_string(board))} (#{total} cards):
      #{Enum.join(card_lines, "\n")}
      """
    end
  end

  def format_query_result(:status, %{mainboard: mb, sideboard: sb, valid: valid, errors: errors}) do
    status = if valid, do: "✓ Legal", else: "✗ Invalid"
    error_text = if Enum.empty?(errors), do: "", else: "\nIssues: #{Enum.join(errors, ", ")}"

    """
    Deck Status: #{status}
    Mainboard: #{mb}/60 cards
    Sideboard: #{sb}/15 cards#{error_text}
    """
  end

  @doc """
  Formats an error message.
  """
  @spec format_error(atom(), map()) :: String.t()
  def format_error(:not_found, %{name: name, suggestions: suggestions}) do
    if Enum.empty?(suggestions) do
      "No card found matching \"#{name}\""
    else
      suggestion_text = suggestions |> Enum.take(3) |> Enum.join(", ")
      "No card found matching \"#{name}\". Did you mean: #{suggestion_text}?"
    end
  end

  def format_error(:copy_limit, %{card: card, current: current, max: max}) do
    "Cannot exceed #{max} copies of #{card.name} (currently have #{current})"
  end

  def format_error(:format_illegal, %{card: card, format: format, reason: reason}) do
    "#{card.name} is #{reason} in #{format}"
  end

  def format_error(:sideboard_full, %{current: current}) do
    "Sideboard is full (#{current}/15 cards)"
  end

  def format_error(:card_not_in_deck, %{name: name, board: board}) do
    "#{name} is not in your #{board}"
  end

  def format_error(:nothing_to_undo, _) do
    "Nothing to undo"
  end

  def format_error(:api_unavailable, _) do
    "AI temporarily unavailable, please use UI controls"
  end

  def format_error(:invalid_command, %{input: input}) do
    "I didn't understand \"#{input}\". Try 'add 4 lightning bolt' or type 'help'"
  end

  def format_error(:restricted_limit, %{card: card}) do
    "#{card.name} is restricted in Vintage (max 1 copy)"
  end

  def format_error(error_type, details) do
    "Error (#{error_type}): #{inspect(details)}"
  end

  @doc """
  Formats disambiguation options.
  """
  @spec format_disambiguation([Card.t()]) :: String.t()
  def format_disambiguation(cards) do
    options =
      cards
      |> Enum.with_index(1)
      |> Enum.map(fn {card, idx} ->
        set = card.set_code || "???"
        "#{idx}. #{card.name} (#{String.upcase(set)})"
      end)

    """
    Multiple cards match. Which did you mean?
    #{Enum.join(options, "\n")}

    Reply with the number to select.
    """
  end
end
