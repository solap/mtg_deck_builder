defmodule MtgDeckBuilder.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scryfall_id, :string, null: false
      add :oracle_id, :string
      add :name, :string, null: false
      add :mana_cost, :string
      add :cmc, :float
      add :type_line, :string
      add :oracle_text, :text
      add :colors, {:array, :string}, default: []
      add :color_identity, {:array, :string}, default: []
      add :legalities, :map, default: %{}
      add :prices, :map, default: %{}
      add :is_basic_land, :boolean, default: false
      add :rarity, :string
      add :set_code, :string

      timestamps()
    end

    create unique_index(:cards, [:scryfall_id])
    create index(:cards, [:name])
    create index(:cards, [:oracle_id])

    # Full-text search index using PostgreSQL tsvector
    execute(
      "CREATE INDEX cards_name_trgm_idx ON cards USING gin (name gin_trgm_ops)",
      "DROP INDEX cards_name_trgm_idx"
    )
  end
end
