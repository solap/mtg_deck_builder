defmodule MtgDeckBuilder.AI.ParsedCommand do
  @moduledoc """
  Represents a structured command parsed from natural language input.

  The AI parses user commands like "add 4 lightning bolt" into this struct
  for execution by the CommandExecutor.
  """

  @type action :: :add | :remove | :set | :move | :query | :undo | :help
  @type board :: :mainboard | :sideboard
  @type query_type :: :count | :list | :status

  @type t :: %__MODULE__{
          action: action(),
          card_name: String.t() | nil,
          quantity: pos_integer(),
          source_board: board() | nil,
          target_board: board(),
          query_type: query_type() | nil,
          raw_input: String.t(),
          confidence: float()
        }

  defstruct [
    :action,
    :card_name,
    quantity: 1,
    source_board: nil,
    target_board: :mainboard,
    query_type: nil,
    raw_input: "",
    confidence: 1.0
  ]

  @valid_actions [:add, :remove, :set, :move, :query, :undo, :help]
  @valid_boards [:mainboard, :sideboard]
  @valid_query_types [:count, :list, :status]

  @doc """
  Validates a ParsedCommand struct.

  Returns `{:ok, command}` if valid, `{:error, reason}` otherwise.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = command) do
    with :ok <- validate_action(command.action),
         :ok <- validate_quantity(command.quantity),
         :ok <- validate_card_name_required(command),
         :ok <- validate_boards(command),
         :ok <- validate_query_type(command) do
      {:ok, command}
    end
  end

  @doc """
  Returns true if the command is valid.
  """
  @spec valid?(t()) :: boolean()
  def valid?(%__MODULE__{} = command) do
    case validate(command) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Creates a ParsedCommand from a map (typically from AI response).
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(attrs) when is_map(attrs) do
    command = %__MODULE__{
      action: parse_action(attrs["action"] || attrs[:action]),
      card_name: attrs["card_name"] || attrs[:card_name],
      quantity: parse_quantity(attrs["quantity"] || attrs[:quantity]),
      source_board: parse_board(attrs["source_board"] || attrs[:source_board]),
      target_board: parse_board(attrs["target_board"] || attrs[:target_board]) || :mainboard,
      query_type: parse_query_type(attrs["query_type"] || attrs[:query_type]),
      raw_input: attrs["raw_input"] || attrs[:raw_input] || "",
      confidence: attrs["confidence"] || attrs[:confidence] || 1.0
    }

    validate(command)
  end

  # Private validation functions

  defp validate_action(action) when action in @valid_actions, do: :ok
  defp validate_action(nil), do: {:error, "action is required"}
  defp validate_action(action), do: {:error, "invalid action: #{inspect(action)}"}

  defp validate_quantity(q) when is_integer(q) and q >= 1 and q <= 15, do: :ok
  defp validate_quantity(q), do: {:error, "quantity must be between 1 and 15, got: #{inspect(q)}"}

  defp validate_card_name_required(%{action: action, card_name: nil})
       when action in [:add, :remove, :set, :move] do
    {:error, "card_name is required for #{action} action"}
  end

  defp validate_card_name_required(_), do: :ok

  defp validate_boards(%{action: :move, target_board: nil}) do
    {:error, "target_board is required for move action"}
  end

  defp validate_boards(%{source_board: board}) when not is_nil(board) and board not in @valid_boards do
    {:error, "invalid source_board: #{inspect(board)}"}
  end

  defp validate_boards(%{target_board: board}) when not is_nil(board) and board not in @valid_boards do
    {:error, "invalid target_board: #{inspect(board)}"}
  end

  defp validate_boards(_), do: :ok

  defp validate_query_type(%{action: :query, query_type: nil}) do
    {:error, "query_type is required for query action"}
  end

  defp validate_query_type(%{query_type: qt}) when not is_nil(qt) and qt not in @valid_query_types do
    {:error, "invalid query_type: #{inspect(qt)}"}
  end

  defp validate_query_type(_), do: :ok

  # Private parsing functions

  defp parse_action(nil), do: nil
  defp parse_action(action) when is_atom(action), do: action

  defp parse_action(action) when is_binary(action) do
    case String.downcase(action) do
      "add" -> :add
      "remove" -> :remove
      "delete" -> :remove
      "set" -> :set
      "move" -> :move
      "query" -> :query
      "undo" -> :undo
      "help" -> :help
      _ -> nil
    end
  end

  defp parse_quantity(nil), do: 1
  defp parse_quantity(q) when is_integer(q), do: max(1, min(15, q))
  defp parse_quantity(q) when is_binary(q), do: parse_quantity(String.to_integer(q))

  defp parse_board(nil), do: nil
  defp parse_board(board) when is_atom(board), do: board

  defp parse_board(board) when is_binary(board) do
    case String.downcase(board) do
      "mainboard" -> :mainboard
      "mb" -> :mainboard
      "main" -> :mainboard
      "sideboard" -> :sideboard
      "sb" -> :sideboard
      "side" -> :sideboard
      _ -> nil
    end
  end

  defp parse_query_type(nil), do: nil
  defp parse_query_type(qt) when is_atom(qt), do: qt

  defp parse_query_type(qt) when is_binary(qt) do
    case String.downcase(qt) do
      "count" -> :count
      "list" -> :list
      "status" -> :status
      _ -> nil
    end
  end
end
