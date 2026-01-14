defmodule MtgDeckBuilder.AI.ParsedCommandTest do
  use ExUnit.Case, async: true

  alias MtgDeckBuilder.AI.ParsedCommand

  describe "validate/1" do
    test "validates a valid add command" do
      command = %ParsedCommand{
        action: :add,
        card_name: "Lightning Bolt",
        quantity: 4,
        target_board: :mainboard
      }

      assert {:ok, ^command} = ParsedCommand.validate(command)
    end

    test "validates a valid remove command" do
      command = %ParsedCommand{
        action: :remove,
        card_name: "Counterspell",
        quantity: 2,
        source_board: :sideboard
      }

      assert {:ok, ^command} = ParsedCommand.validate(command)
    end

    test "validates a valid move command" do
      command = %ParsedCommand{
        action: :move,
        card_name: "Thoughtseize",
        quantity: 1,
        source_board: :mainboard,
        target_board: :sideboard
      }

      assert {:ok, ^command} = ParsedCommand.validate(command)
    end

    test "validates a valid query command" do
      command = %ParsedCommand{
        action: :query,
        query_type: :status
      }

      assert {:ok, ^command} = ParsedCommand.validate(command)
    end

    test "validates undo command" do
      command = %ParsedCommand{action: :undo}
      assert {:ok, ^command} = ParsedCommand.validate(command)
    end

    test "validates help command" do
      command = %ParsedCommand{action: :help}
      assert {:ok, ^command} = ParsedCommand.validate(command)
    end

    test "rejects command with nil action" do
      command = %ParsedCommand{action: nil}
      assert {:error, "action is required"} = ParsedCommand.validate(command)
    end

    test "rejects command with invalid action" do
      command = %ParsedCommand{action: :invalid}
      assert {:error, "invalid action: :invalid"} = ParsedCommand.validate(command)
    end

    test "rejects add command without card_name" do
      command = %ParsedCommand{action: :add, card_name: nil}
      assert {:error, "card_name is required for add action"} = ParsedCommand.validate(command)
    end

    test "rejects remove command without card_name" do
      command = %ParsedCommand{action: :remove, card_name: nil}
      assert {:error, "card_name is required for remove action"} = ParsedCommand.validate(command)
    end

    test "rejects set command without card_name" do
      command = %ParsedCommand{action: :set, card_name: nil}
      assert {:error, "card_name is required for set action"} = ParsedCommand.validate(command)
    end

    test "rejects move command without card_name" do
      command = %ParsedCommand{action: :move, card_name: nil}
      assert {:error, "card_name is required for move action"} = ParsedCommand.validate(command)
    end

    test "rejects query command without query_type" do
      command = %ParsedCommand{action: :query, query_type: nil}
      assert {:error, "query_type is required for query action"} = ParsedCommand.validate(command)
    end

    test "rejects invalid quantity (0)" do
      command = %ParsedCommand{action: :add, card_name: "Bolt", quantity: 0}
      assert {:error, "quantity must be between 1 and 15" <> _} = ParsedCommand.validate(command)
    end

    test "rejects invalid quantity (16)" do
      command = %ParsedCommand{action: :add, card_name: "Bolt", quantity: 16}
      assert {:error, "quantity must be between 1 and 15" <> _} = ParsedCommand.validate(command)
    end

    test "rejects invalid source_board" do
      command = %ParsedCommand{
        action: :remove,
        card_name: "Bolt",
        source_board: :invalid_board
      }

      assert {:error, "invalid source_board: :invalid_board"} = ParsedCommand.validate(command)
    end

    test "rejects invalid target_board" do
      command = %ParsedCommand{
        action: :add,
        card_name: "Bolt",
        target_board: :invalid_board
      }

      assert {:error, "invalid target_board: :invalid_board"} = ParsedCommand.validate(command)
    end

    test "rejects invalid query_type" do
      command = %ParsedCommand{action: :query, query_type: :invalid}
      assert {:error, "invalid query_type: :invalid"} = ParsedCommand.validate(command)
    end
  end

  describe "valid?/1" do
    test "returns true for valid command" do
      command = %ParsedCommand{
        action: :add,
        card_name: "Lightning Bolt",
        quantity: 4
      }

      assert ParsedCommand.valid?(command)
    end

    test "returns false for invalid command" do
      command = %ParsedCommand{action: nil}
      refute ParsedCommand.valid?(command)
    end
  end

  describe "from_map/1" do
    test "creates command from map with string keys" do
      attrs = %{
        "action" => "add",
        "card_name" => "Lightning Bolt",
        "quantity" => 4,
        "target_board" => "mainboard"
      }

      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.action == :add
      assert command.card_name == "Lightning Bolt"
      assert command.quantity == 4
      assert command.target_board == :mainboard
    end

    test "creates command from map with atom keys" do
      attrs = %{
        action: :remove,
        card_name: "Counterspell",
        quantity: 2,
        source_board: :sideboard
      }

      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.action == :remove
      assert command.card_name == "Counterspell"
      assert command.quantity == 2
      assert command.source_board == :sideboard
    end

    test "parses action string 'delete' as :remove" do
      attrs = %{"action" => "delete", "card_name" => "Bolt"}
      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.action == :remove
    end

    test "parses board abbreviations" do
      attrs = %{
        "action" => "move",
        "card_name" => "Bolt",
        "source_board" => "mb",
        "target_board" => "sb"
      }

      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.source_board == :mainboard
      assert command.target_board == :sideboard
    end

    test "parses staging board variants" do
      attrs = %{
        "action" => "add",
        "card_name" => "Bolt",
        "target_board" => "staging"
      }

      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.target_board == :staging

      attrs2 = %{
        "action" => "add",
        "card_name" => "Bolt",
        "target_board" => "stage"
      }

      assert {:ok, command2} = ParsedCommand.from_map(attrs2)
      assert command2.target_board == :staging
    end

    test "defaults quantity to 1 when not provided" do
      attrs = %{"action" => "add", "card_name" => "Bolt"}
      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.quantity == 1
    end

    test "defaults target_board to mainboard when not provided" do
      attrs = %{"action" => "add", "card_name" => "Bolt"}
      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.target_board == :mainboard
    end

    test "clamps quantity to valid range" do
      attrs = %{"action" => "add", "card_name" => "Bolt", "quantity" => 100}
      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.quantity == 15
    end

    test "preserves raw_input" do
      attrs = %{
        "action" => "add",
        "card_name" => "Bolt",
        "raw_input" => "add 4 bolts"
      }

      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.raw_input == "add 4 bolts"
    end

    test "preserves confidence" do
      attrs = %{
        "action" => "add",
        "card_name" => "Bolt",
        "confidence" => 0.95
      }

      assert {:ok, command} = ParsedCommand.from_map(attrs)
      assert command.confidence == 0.95
    end

    test "returns error for invalid command" do
      attrs = %{"action" => "invalid_action"}
      assert {:error, _} = ParsedCommand.from_map(attrs)
    end
  end
end
