defmodule MtgDeckBuilder.AI.ApiUsageLog do
  @moduledoc """
  Ecto schema for tracking AI API usage and costs.

  Each API call is logged with provider, token counts, and estimated cost
  for monitoring and billing purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          provider: String.t(),
          model: String.t(),
          input_tokens: non_neg_integer(),
          output_tokens: non_neg_integer(),
          estimated_cost_cents: non_neg_integer(),
          latency_ms: non_neg_integer(),
          success: boolean(),
          error_type: String.t() | nil,
          endpoint: String.t(),
          inserted_at: DateTime.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "api_usage_logs" do
    field :provider, :string
    field :model, :string
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :estimated_cost_cents, :integer, default: 0
    field :latency_ms, :integer, default: 0
    field :success, :boolean, default: true
    field :error_type, :string
    field :endpoint, :string

    timestamps(updated_at: false)
  end

  @required_fields [:provider, :model, :endpoint]
  @optional_fields [:input_tokens, :output_tokens, :estimated_cost_cents, :latency_ms, :success, :error_type]

  @doc """
  Creates a changeset for an API usage log.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = log, attrs) do
    log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:provider, ["anthropic", "openai", "xai"])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:estimated_cost_cents, greater_than_or_equal_to: 0)
    |> validate_number(:latency_ms, greater_than_or_equal_to: 0)
  end
end
