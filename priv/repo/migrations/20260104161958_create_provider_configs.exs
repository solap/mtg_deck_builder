defmodule MtgDeckBuilder.Repo.Migrations.CreateProviderConfigs do
  use Ecto.Migration

  def change do
    create table(:provider_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :api_key_env, :string, null: false
      add :base_url, :string
      add :enabled, :boolean, default: true

      timestamps()
    end

    create unique_index(:provider_configs, [:provider])
  end
end
