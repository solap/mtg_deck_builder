defmodule MtgDeckBuilder.AI.ApiLogger do
  @moduledoc """
  Logs AI API usage to the database for cost tracking.
  """

  alias MtgDeckBuilder.Repo
  alias MtgDeckBuilder.AI.ApiUsageLog

  @doc """
  Logs an API request to the database.

  ## Parameters
    - attrs: Map with keys:
      - provider: "anthropic" | "openai" | "xai"
      - model: Model identifier string
      - endpoint: API endpoint called
      - input_tokens: Number of input tokens
      - output_tokens: Number of output tokens
      - latency_ms: Request duration in milliseconds
      - success: Boolean indicating success
      - error_type: Error type string (if failed)

  ## Returns
    - {:ok, log} on success
    - {:error, changeset} on failure
  """
  @spec log_request(map()) :: {:ok, ApiUsageLog.t()} | {:error, Ecto.Changeset.t()}
  def log_request(attrs) do
    attrs_with_cost = Map.put(attrs, :estimated_cost_cents, calculate_cost(attrs))

    %ApiUsageLog{}
    |> ApiUsageLog.changeset(attrs_with_cost)
    |> Repo.insert()
  end

  @doc """
  Calculates estimated cost in cents based on provider and token counts.

  ## Pricing (as of 2024):
    - Claude 3 Haiku: $0.25/1M input, $1.25/1M output
    - Claude 3 Sonnet: $3/1M input, $15/1M output
    - GPT-4: $30/1M input, $60/1M output
    - GPT-3.5 Turbo: $0.50/1M input, $1.50/1M output
  """
  @spec calculate_cost(map()) :: non_neg_integer()
  def calculate_cost(%{provider: "anthropic", model: model} = attrs) do
    input_tokens = attrs[:input_tokens] || 0
    output_tokens = attrs[:output_tokens] || 0

    {input_rate, output_rate} =
      cond do
        String.contains?(model, "haiku") -> {0.25, 1.25}
        String.contains?(model, "sonnet") -> {3.0, 15.0}
        String.contains?(model, "opus") -> {15.0, 75.0}
        true -> {0.25, 1.25}
      end

    # Cost in cents (rates are per 1M tokens, so divide by 1M and multiply by 100 for cents)
    input_cost = input_tokens * input_rate / 1_000_000 * 100
    output_cost = output_tokens * output_rate / 1_000_000 * 100

    trunc(input_cost + output_cost)
  end

  def calculate_cost(%{provider: "openai", model: model} = attrs) do
    input_tokens = attrs[:input_tokens] || 0
    output_tokens = attrs[:output_tokens] || 0

    {input_rate, output_rate} =
      cond do
        String.contains?(model, "gpt-4") -> {30.0, 60.0}
        String.contains?(model, "gpt-3.5") -> {0.50, 1.50}
        true -> {0.50, 1.50}
      end

    input_cost = input_tokens * input_rate / 1_000_000 * 100
    output_cost = output_tokens * output_rate / 1_000_000 * 100

    trunc(input_cost + output_cost)
  end

  def calculate_cost(%{provider: "xai"} = attrs) do
    input_tokens = attrs[:input_tokens] || 0
    output_tokens = attrs[:output_tokens] || 0

    # xAI Grok pricing (estimated)
    input_cost = input_tokens * 5.0 / 1_000_000 * 100
    output_cost = output_tokens * 15.0 / 1_000_000 * 100

    trunc(input_cost + output_cost)
  end

  def calculate_cost(_), do: 0
end
