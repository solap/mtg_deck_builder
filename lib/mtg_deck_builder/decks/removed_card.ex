defmodule MtgDeckBuilder.Decks.RemovedCard do
  @moduledoc """
  Represents a card that was removed from the deck due to format restrictions.
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
    :is_basic_land,
    :removal_reason,
    :original_board
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
          is_basic_land: boolean(),
          removal_reason: String.t(),
          original_board: :mainboard | :sideboard
        }

  @doc """
  Creates a RemovedCard from a DeckCard.
  """
  def from_deck_card(%MtgDeckBuilder.Decks.DeckCard{} = card, reason, board) do
    %__MODULE__{
      scryfall_id: card.scryfall_id,
      name: card.name,
      quantity: card.quantity,
      mana_cost: card.mana_cost,
      cmc: card.cmc,
      type_line: card.type_line,
      oracle_text: card.oracle_text,
      colors: card.colors,
      price: card.price,
      is_basic_land: card.is_basic_land,
      removal_reason: reason,
      original_board: board
    }
  end
end
