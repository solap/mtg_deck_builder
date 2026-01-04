defmodule MtgDeckBuilder.Decks.Deck do
  @moduledoc """
  Represents a deck with mainboard, sideboard, and removed cards.
  This is stored client-side in localStorage.
  """

  alias MtgDeckBuilder.Decks.DeckCard

  @derive Jason.Encoder
  defstruct [
    :id,
    :name,
    :format,
    mainboard: [],
    sideboard: [],
    removed_cards: [],
    created_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          format: atom(),
          mainboard: [DeckCard.t()],
          sideboard: [DeckCard.t()],
          removed_cards: [map()],
          created_at: String.t() | nil,
          updated_at: String.t() | nil
        }

  @doc """
  Creates a new empty deck with a generated ID.
  """
  def new(format \\ :modern, name \\ "New Deck") do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      name: name,
      format: format,
      mainboard: [],
      sideboard: [],
      removed_cards: [],
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Returns the total number of cards in the mainboard.
  """
  def mainboard_count(%__MODULE__{mainboard: mainboard}) do
    Enum.reduce(mainboard, 0, fn card, acc -> acc + card.quantity end)
  end

  @doc """
  Returns the total number of cards in the sideboard.
  """
  def sideboard_count(%__MODULE__{sideboard: sideboard}) do
    Enum.reduce(sideboard, 0, fn card, acc -> acc + card.quantity end)
  end

  @doc """
  Returns the total number of copies of a specific card across both boards.
  """
  def card_count(%__MODULE__{mainboard: mainboard, sideboard: sideboard}, scryfall_id) do
    main_count =
      Enum.find(mainboard, fn c -> c.scryfall_id == scryfall_id end)
      |> case do
        nil -> 0
        card -> card.quantity
      end

    side_count =
      Enum.find(sideboard, fn c -> c.scryfall_id == scryfall_id end)
      |> case do
        nil -> 0
        card -> card.quantity
      end

    main_count + side_count
  end
end
