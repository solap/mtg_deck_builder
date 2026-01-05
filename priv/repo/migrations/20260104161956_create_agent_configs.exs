defmodule MtgDeckBuilder.Repo.Migrations.CreateAgentConfigs do
  use Ecto.Migration

  def change do
    create table(:agent_configs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, :string, null: false
      add :name, :string, null: false
      add :description, :text
      add :provider, :string, null: false
      add :model, :string, null: false
      add :system_prompt, :text, null: false
      add :default_prompt, :text, null: false
      add :max_tokens, :integer, default: 1024
      add :context_window, :integer, default: 200_000
      add :temperature, :decimal, precision: 3, scale: 2, default: 0.7
      add :enabled, :boolean, default: true
      add :cost_per_1k_input, :decimal, precision: 10, scale: 6
      add :cost_per_1k_output, :decimal, precision: 10, scale: 6

      timestamps()
    end

    create unique_index(:agent_configs, [:agent_id])
  end
end
