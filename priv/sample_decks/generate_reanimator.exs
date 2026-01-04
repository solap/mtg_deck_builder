alias MtgDeckBuilder.Cards
alias MtgDeckBuilder.Decks.DeckCard

mainboard = [
  {"Swamp", 1}, {"Willowrush Verge", 2}, {"Underground Mortuary", 2},
  {"Hedge Maze", 1}, {"Harvester of Misery", 2}, {"Awaken the Honored Dead", 4},
  {"Bringer of the Last Gift", 4}, {"Breeding Pool", 4}, {"Island", 1},
  {"Wastewood Verge", 3}, {"Cavern of Souls", 1}, {"Blooming Marsh", 3},
  {"Ardyn, the Usurper", 3}, {"Superior Spider-Man", 4}, {"Bitter Triumph", 4},
  {"Broodspinner", 4}, {"Multiversal Passage", 1}, {"Undercity Sewers", 1},
  {"Analyze the Pollen", 3}, {"Oblivious Bookworm", 4}, {"Watery Grave", 3},
  {"Terror of the Peaks", 1}, {"Overlord of the Balemurk", 4}
]

sideboard = [
  {"Webstrike Elite", 1}, {"Deep-Cavern Bat", 3}, {"Intimidation Tactics", 4},
  {"Urgent Necropsy", 1}, {"Glarb, Calamity's Augur", 2}, {"Cavern of Souls", 1},
  {"Disruptive Stormbrood", 1}, {"Soul-Guide Lantern", 2}
]

build_deck_cards = fn cards ->
  Enum.map(cards, fn {name, qty} ->
    case Cards.search(name, limit: 1) do
      [card | _] -> DeckCard.from_card(card, qty)
      [] -> raise "Card not found: #{name}"
    end
  end)
end

mainboard_cards = build_deck_cards.(mainboard)
sideboard_cards = build_deck_cards.(sideboard)

deck = %{
  id: Ecto.UUID.generate(),
  name: "4c Reanimator",
  format: :standard,
  mainboard: mainboard_cards,
  sideboard: sideboard_cards,
  removed_cards: [],
  created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
  updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
}

json = Jason.encode!(deck, pretty: true)
File.write!("priv/sample_decks/reanimator_4c.json", json)

main_total = Enum.sum(Enum.map(mainboard_cards, & &1.quantity))
side_total = Enum.sum(Enum.map(sideboard_cards, & &1.quantity))

IO.puts("Deck saved to priv/sample_decks/reanimator_4c.json")
IO.puts("Mainboard: #{length(mainboard_cards)} unique cards, #{main_total} total")
IO.puts("Sideboard: #{length(sideboard_cards)} unique cards, #{side_total} total")
