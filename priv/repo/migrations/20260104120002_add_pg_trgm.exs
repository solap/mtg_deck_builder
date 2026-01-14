defmodule MtgDeckBuilder.Repo.Migrations.AddPgTrgm do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"

    # Add trigram index on card names for fuzzy search
    execute """
    CREATE INDEX IF NOT EXISTS cards_name_trgm_idx
    ON cards USING gin (name gin_trgm_ops)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS cards_name_trgm_idx"
    execute "DROP EXTENSION IF EXISTS pg_trgm"
  end
end
