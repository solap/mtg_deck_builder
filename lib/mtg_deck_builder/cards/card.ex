defmodule MtgDeckBuilder.Cards.Card do
  @moduledoc """
  Schema for Magic: The Gathering cards.
  Data is imported from Scryfall bulk data (oracle-cards).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cards" do
    field :scryfall_id, :string
    field :oracle_id, :string
    field :name, :string
    field :mana_cost, :string
    field :cmc, :float
    field :type_line, :string
    field :oracle_text, :string
    field :colors, {:array, :string}, default: []
    field :color_identity, {:array, :string}, default: []
    field :legalities, :map, default: %{}
    field :prices, :map, default: %{}
    field :is_basic_land, :boolean, default: false
    field :rarity, :string
    field :set_code, :string

    timestamps()
  end

  @doc false
  def changeset(card, attrs) do
    card
    |> cast(attrs, [
      :scryfall_id,
      :oracle_id,
      :name,
      :mana_cost,
      :cmc,
      :type_line,
      :oracle_text,
      :colors,
      :color_identity,
      :legalities,
      :prices,
      :is_basic_land,
      :rarity,
      :set_code
    ])
    |> validate_required([:scryfall_id, :name])
    |> unique_constraint(:scryfall_id)
  end
end
