defmodule MtgDeckBuilder.CardsTest do
  use MtgDeckBuilder.DataCase, async: true

  alias MtgDeckBuilder.Cards
  alias MtgDeckBuilder.Cards.Card

  describe "search/2" do
    setup do
      # Insert test cards
      {:ok, lightning_bolt} =
        %Card{}
        |> Card.changeset(%{
          scryfall_id: "test-lightning-bolt",
          oracle_id: "oracle-bolt",
          name: "Lightning Bolt",
          mana_cost: "{R}",
          cmc: 1.0,
          type_line: "Instant",
          oracle_text: "Lightning Bolt deals 3 damage to any target.",
          colors: ["R"],
          color_identity: ["R"],
          legalities: %{"modern" => "legal", "standard" => "not_legal", "pauper" => "legal"},
          prices: %{"usd" => "1.50"},
          is_basic_land: false,
          rarity: "common",
          set_code: "lea"
        })
        |> Repo.insert()

      {:ok, counterspell} =
        %Card{}
        |> Card.changeset(%{
          scryfall_id: "test-counterspell",
          oracle_id: "oracle-counter",
          name: "Counterspell",
          mana_cost: "{U}{U}",
          cmc: 2.0,
          type_line: "Instant",
          oracle_text: "Counter target spell.",
          colors: ["U"],
          color_identity: ["U"],
          legalities: %{"modern" => "not_legal", "legacy" => "legal", "pauper" => "legal"},
          prices: %{"usd" => "2.00"},
          is_basic_land: false,
          rarity: "common",
          set_code: "lea"
        })
        |> Repo.insert()

      {:ok, mountain} =
        %Card{}
        |> Card.changeset(%{
          scryfall_id: "test-mountain",
          oracle_id: "oracle-mountain",
          name: "Mountain",
          mana_cost: nil,
          cmc: 0.0,
          type_line: "Basic Land — Mountain",
          oracle_text: "({T}: Add {R}.)",
          colors: [],
          color_identity: ["R"],
          legalities: %{"modern" => "legal", "standard" => "legal", "pauper" => "legal"},
          prices: %{"usd" => "0.10"},
          is_basic_land: true,
          rarity: "common",
          set_code: "lea"
        })
        |> Repo.insert()

      %{lightning_bolt: lightning_bolt, counterspell: counterspell, mountain: mountain}
    end

    test "returns cards matching name", %{lightning_bolt: bolt} do
      results = Cards.search("Lightning")
      assert length(results) == 1
      assert hd(results).scryfall_id == bolt.scryfall_id
    end

    test "search is case-insensitive", %{lightning_bolt: bolt} do
      results = Cards.search("lightning bolt")
      assert length(results) == 1
      assert hd(results).scryfall_id == bolt.scryfall_id
    end

    test "returns multiple matching cards", _context do
      # Both have 'ount' in name - use partial match
      results = Cards.search("ount")
      names = Enum.map(results, & &1.name)
      assert "Mountain" in names
      assert "Counterspell" in names
    end

    test "returns empty list when no cards match" do
      results = Cards.search("Nonexistent Card XYZ")
      assert results == []
    end

    test "filters by format when format option provided", %{lightning_bolt: bolt} do
      # Lightning Bolt is legal in modern
      results = Cards.search("bolt", format: :modern)
      assert length(results) == 1
      assert hd(results).scryfall_id == bolt.scryfall_id

      # Lightning Bolt is not legal in standard
      results = Cards.search("bolt", format: :standard)
      assert results == []
    end

    test "filters by format as string", %{lightning_bolt: bolt} do
      results = Cards.search("bolt", format: "modern")
      assert length(results) == 1
      assert hd(results).scryfall_id == bolt.scryfall_id
    end

    test "respects limit option" do
      results = Cards.search("", limit: 1)
      assert length(results) == 1
    end
  end

  describe "get_by_scryfall_id/1" do
    setup do
      {:ok, card} =
        %Card{}
        |> Card.changeset(%{
          scryfall_id: "unique-scryfall-id-123",
          name: "Test Card"
        })
        |> Repo.insert()

      %{card: card}
    end

    test "returns card when scryfall_id exists", %{card: card} do
      result = Cards.get_by_scryfall_id("unique-scryfall-id-123")
      assert result.id == card.id
      assert result.name == "Test Card"
    end

    test "returns nil when scryfall_id does not exist" do
      result = Cards.get_by_scryfall_id("nonexistent-id")
      assert result == nil
    end
  end

  describe "count/0" do
    test "returns 0 when no cards exist" do
      assert Cards.count() == 0
    end

    test "returns correct count after inserting cards" do
      for i <- 1..5 do
        %Card{}
        |> Card.changeset(%{scryfall_id: "card-#{i}", name: "Card #{i}"})
        |> Repo.insert!()
      end

      assert Cards.count() == 5
    end
  end

  describe "upsert/1" do
    test "inserts new card" do
      attrs = %{scryfall_id: "new-card-id", name: "New Card"}
      assert {:ok, card} = Cards.upsert(attrs)
      assert card.scryfall_id == "new-card-id"
      assert card.name == "New Card"
    end

    test "updates existing card on conflict" do
      %Card{}
      |> Card.changeset(%{scryfall_id: "existing-id", name: "Original Name"})
      |> Repo.insert!()

      attrs = %{scryfall_id: "existing-id", name: "Updated Name"}
      assert {:ok, card} = Cards.upsert(attrs)
      assert card.name == "Updated Name"
      assert Cards.count() == 1
    end
  end

  describe "insert_all/1" do
    test "inserts multiple cards in batch" do
      cards = [
        %{scryfall_id: "batch-1", name: "Batch Card 1"},
        %{scryfall_id: "batch-2", name: "Batch Card 2"},
        %{scryfall_id: "batch-3", name: "Batch Card 3"}
      ]

      {count, _} = Cards.insert_all(cards)
      assert count == 3
      assert Cards.count() == 3
    end

    test "handles upsert on conflict" do
      %Card{}
      |> Card.changeset(%{scryfall_id: "existing-batch", name: "Original"})
      |> Repo.insert!()

      cards = [
        %{scryfall_id: "existing-batch", name: "Updated"},
        %{scryfall_id: "new-batch", name: "New Card"}
      ]

      {count, _} = Cards.insert_all(cards)
      assert count == 2
      assert Cards.count() == 2

      updated = Cards.get_by_scryfall_id("existing-batch")
      assert updated.name == "Updated"
    end
  end
end
