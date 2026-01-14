defmodule MtgDeckBuilder.Cards.BulkImporterTest do
  use ExUnit.Case, async: true

  alias MtgDeckBuilder.Cards.BulkImporter

  describe "transform_card/1" do
    test "transforms basic card with all fields" do
      scryfall_card = %{
        "id" => "abc123",
        "oracle_id" => "oracle-abc",
        "name" => "Lightning Bolt",
        "mana_cost" => "{R}",
        "cmc" => 1.0,
        "type_line" => "Instant",
        "oracle_text" => "Lightning Bolt deals 3 damage to any target.",
        "colors" => ["R"],
        "color_identity" => ["R"],
        "legalities" => %{"modern" => "legal", "standard" => "not_legal"},
        "prices" => %{"usd" => "1.50", "usd_foil" => "3.00", "eur" => "1.20"},
        "rarity" => "common",
        "set" => "lea"
      }

      result = BulkImporter.transform_card(scryfall_card)

      assert result.scryfall_id == "abc123"
      assert result.oracle_id == "oracle-abc"
      assert result.name == "Lightning Bolt"
      assert result.mana_cost == "{R}"
      assert result.cmc == 1.0
      assert result.type_line == "Instant"
      assert result.oracle_text == "Lightning Bolt deals 3 damage to any target."
      assert result.colors == ["R"]
      assert result.color_identity == ["R"]
      assert result.legalities == %{"modern" => "legal", "standard" => "not_legal"}
      assert result.prices == %{"usd" => "1.50", "usd_foil" => "3.00"}
      assert result.is_basic_land == false
      assert result.rarity == "common"
      assert result.set_code == "lea"
    end

    test "handles basic land detection" do
      basic_land = %{
        "id" => "mountain-id",
        "name" => "Mountain",
        "type_line" => "Basic Land — Mountain",
        "mana_cost" => nil
      }

      result = BulkImporter.transform_card(basic_land)
      assert result.is_basic_land == true
    end

    test "handles non-basic land" do
      nonbasic_land = %{
        "id" => "steam-vents-id",
        "name" => "Steam Vents",
        "type_line" => "Land — Island Mountain"
      }

      result = BulkImporter.transform_card(nonbasic_land)
      assert result.is_basic_land == false
    end

    test "handles missing optional fields with defaults" do
      minimal_card = %{
        "id" => "minimal-id",
        "name" => "Minimal Card"
      }

      result = BulkImporter.transform_card(minimal_card)

      assert result.scryfall_id == "minimal-id"
      assert result.name == "Minimal Card"
      assert result.colors == []
      assert result.color_identity == []
      assert result.legalities == %{}
      assert result.prices == %{}
      assert result.is_basic_land == false
      assert result.mana_cost == nil
      assert result.oracle_text == nil
    end

    test "handles nil colors and color_identity" do
      card_with_nil = %{
        "id" => "colorless-id",
        "name" => "Sol Ring",
        "colors" => nil,
        "color_identity" => nil
      }

      result = BulkImporter.transform_card(card_with_nil)
      assert result.colors == []
      assert result.color_identity == []
    end

    test "handles nil prices" do
      card_without_prices = %{
        "id" => "no-price-id",
        "name" => "No Price Card",
        "prices" => nil
      }

      result = BulkImporter.transform_card(card_without_prices)
      assert result.prices == %{}
    end

    test "extracts only usd and usd_foil from prices" do
      card_with_all_prices = %{
        "id" => "priced-id",
        "name" => "Priced Card",
        "prices" => %{
          "usd" => "10.00",
          "usd_foil" => "25.00",
          "usd_etched" => "15.00",
          "eur" => "8.00",
          "eur_foil" => "20.00",
          "tix" => "5.00"
        }
      }

      result = BulkImporter.transform_card(card_with_all_prices)
      assert result.prices == %{"usd" => "10.00", "usd_foil" => "25.00"}
    end

    test "handles multicolor cards" do
      multicolor_card = %{
        "id" => "multicolor-id",
        "name" => "Nicol Bolas, the Ravager",
        "colors" => ["U", "B", "R"],
        "color_identity" => ["U", "B", "R"],
        "type_line" => "Legendary Creature — Elder Dragon"
      }

      result = BulkImporter.transform_card(multicolor_card)
      assert result.colors == ["U", "B", "R"]
      assert result.color_identity == ["U", "B", "R"]
    end

    test "preserves legalities map structure" do
      card_with_legalities = %{
        "id" => "legal-id",
        "name" => "Legal Card",
        "legalities" => %{
          "standard" => "legal",
          "modern" => "legal",
          "legacy" => "legal",
          "vintage" => "restricted",
          "pauper" => "not_legal"
        }
      }

      result = BulkImporter.transform_card(card_with_legalities)
      assert result.legalities["standard"] == "legal"
      assert result.legalities["vintage"] == "restricted"
      assert result.legalities["pauper"] == "not_legal"
    end
  end
end
