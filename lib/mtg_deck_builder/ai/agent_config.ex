defmodule MtgDeckBuilder.AI.AgentConfig do
  @moduledoc """
  Ecto schema for AI agent configurations.

  Each agent (orchestrator, command_parser, etc.) can be configured with:
  - A specific AI provider and model
  - Editable system prompts
  - Temperature and token settings
  - Cost tracking fields
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @providers ~w(anthropic openai xai ollama)

  schema "agent_configs" do
    field :agent_id, :string
    field :name, :string
    field :description, :string
    field :provider, :string
    field :model, :string
    field :system_prompt, :string
    field :default_prompt, :string
    field :max_tokens, :integer, default: 1024
    field :context_window, :integer, default: 200_000
    field :temperature, :decimal, default: Decimal.new("0.7")
    field :enabled, :boolean, default: true
    field :cost_per_1k_input, :decimal
    field :cost_per_1k_output, :decimal

    timestamps()
  end

  @doc """
  Changeset for creating a new agent config.
  """
  def create_changeset(agent_config, attrs) do
    agent_config
    |> cast(attrs, [
      :agent_id,
      :name,
      :description,
      :provider,
      :model,
      :system_prompt,
      :default_prompt,
      :max_tokens,
      :context_window,
      :temperature,
      :enabled,
      :cost_per_1k_input,
      :cost_per_1k_output
    ])
    |> validate_required([
      :agent_id,
      :name,
      :provider,
      :model,
      :system_prompt,
      :default_prompt
    ])
    |> validate_inclusion(:provider, @providers)
    |> validate_number(:max_tokens, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:context_window, greater_than: 0)
    |> validate_temperature()
    |> unique_constraint(:agent_id)
  end

  @doc """
  Changeset for updating an existing agent config.
  Only allows updating editable fields.
  """
  def update_changeset(agent_config, attrs) do
    agent_config
    |> cast(attrs, [
      :name,
      :description,
      :provider,
      :model,
      :system_prompt,
      :max_tokens,
      :context_window,
      :temperature,
      :enabled,
      :cost_per_1k_input,
      :cost_per_1k_output
    ])
    |> validate_inclusion(:provider, @providers)
    |> validate_number(:max_tokens, greater_than: 0, less_than_or_equal_to: 100_000)
    |> validate_number(:context_window, greater_than: 0)
    |> validate_temperature()
  end

  defp validate_temperature(changeset) do
    case get_change(changeset, :temperature) do
      nil ->
        changeset

      temp ->
        temp_float =
          case temp do
            %Decimal{} -> Decimal.to_float(temp)
            _ -> temp
          end

        if temp_float >= 0.0 and temp_float <= 2.0 do
          changeset
        else
          add_error(changeset, :temperature, "must be between 0.0 and 2.0")
        end
    end
  end

  @doc """
  Returns the list of valid providers.
  """
  def valid_providers, do: @providers
end
