defmodule MtgDeckBuilder.Decks.DeckCard do
  @moduledoc """
  Represents a card in a deck with quantity information.
  This is a denormalized view of a card for efficient deck operations.
  """

  @derive Jason.Encoder
  defstruct [
    :scryfall_id,
    :name,
    :quantity,
    :mana_cost,
    :cmc,
    :type_line,
    :oracle_text,
    :colors,
    :price,
    :is_basic_land
  ]

  @type t :: %__MODULE__{
          scryfall_id: String.t(),
          name: String.t(),
          quantity: pos_integer(),
          mana_cost: String.t() | nil,
          cmc: float(),
          type_line: String.t() | nil,
          oracle_text: String.t() | nil,
          colors: [String.t()],
          price: String.t() | nil,
          is_basic_land: boolean()
        }

  @doc """
  Creates a DeckCard from a Card schema.
  """
  def from_card(%MtgDeckBuilder.Cards.Card{} = card, quantity \\ 1) do
    %__MODULE__{
      scryfall_id: card.scryfall_id,
      name: card.name,
      quantity: quantity,
      mana_cost: card.mana_cost,
      cmc: card.cmc || 0.0,
      type_line: card.type_line,
      oracle_text: card.oracle_text,
      colors: card.colors || [],
      price: get_in(card.prices, ["usd"]),
      is_basic_land: card.is_basic_land
    }
  end
end
