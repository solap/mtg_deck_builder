defmodule MtgDeckBuilder.Repo.Migrations.CreateApiUsageLogs do
  use Ecto.Migration

  def change do
    create table(:api_usage_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false
      add :model, :string, null: false
      add :input_tokens, :integer, null: false, default: 0
      add :output_tokens, :integer, null: false, default: 0
      add :estimated_cost_cents, :integer, null: false, default: 0
      add :latency_ms, :integer, null: false, default: 0
      add :success, :boolean, null: false, default: true
      add :error_type, :string
      add :endpoint, :string, null: false

      timestamps(updated_at: false)
    end

    create index(:api_usage_logs, [:provider])
    create index(:api_usage_logs, [:inserted_at])
    create index(:api_usage_logs, [:provider, :inserted_at])
  end
end
