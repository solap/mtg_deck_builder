defmodule MtgDeckBuilder.Repo.Migrations.AddApiKeyManagementToProviderConfigs do
  use Ecto.Migration

  def change do
    alter table(:provider_configs) do
      # Encrypted API key stored in DB (optional - env var fallback still works)
      add :encrypted_api_key, :binary

      # Key status: not_configured, configured, valid, invalid
      add :key_status, :string, default: "not_configured"

      # When the key was last verified to work
      add :last_verified_at, :utc_datetime

      # Error message if key is invalid
      add :last_error, :string
    end

    # Update existing rows to have correct status based on api_key_env
    execute """
    UPDATE provider_configs
    SET key_status = 'configured'
    WHERE api_key_env IS NOT NULL AND api_key_env != ''
    """, ""
  end
end
