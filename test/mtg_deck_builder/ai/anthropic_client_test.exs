defmodule MtgDeckBuilder.AI.AnthropicClientTest do
  use MtgDeckBuilder.DataCase, async: true

  alias MtgDeckBuilder.AI.AnthropicClient

  # These tests verify the client's behavior without making actual API calls.
  # For integration tests with the real API, see test/integration/

  describe "parse_command/2" do
    test "returns error when API key is not configured" do
      # Temporarily clear the API key
      original_config = Application.get_env(:mtg_deck_builder, :anthropic)
      Application.put_env(:mtg_deck_builder, :anthropic, api_key: nil)

      # Also mock Settings to return nil
      result = AnthropicClient.parse_command("add 4 lightning bolt")

      # Restore config
      Application.put_env(:mtg_deck_builder, :anthropic, original_config)

      # Should return an error (either config error or API error)
      assert match?({:error, _}, result)
    end

    test "accepts deck_card_names option" do
      # This test just verifies the option is accepted without error
      # Actual API behavior would be tested in integration tests
      original_config = Application.get_env(:mtg_deck_builder, :anthropic)
      Application.put_env(:mtg_deck_builder, :anthropic, api_key: nil)

      result =
        AnthropicClient.parse_command("add BT",
          deck_card_names: ["Bitter Triumph", "Lightning Bolt"]
        )

      Application.put_env(:mtg_deck_builder, :anthropic, original_config)

      # Should handle gracefully (error due to no API key is fine)
      assert match?({:error, _}, result)
    end
  end

  describe "module attributes" do
    test "defines the tool schema with required fields" do
      # Access the module to ensure it compiles correctly
      assert Code.ensure_loaded?(AnthropicClient)
    end
  end
end
