defmodule MtgDeckBuilder.AI.CostStats do
  @moduledoc """
  Provides aggregated statistics for API usage and costs.
  """

  import Ecto.Query
  alias MtgDeckBuilder.Repo
  alias MtgDeckBuilder.AI.ApiUsageLog

  @doc """
  Returns aggregate totals for the given date range.

  ## Parameters
    - from_date: Start date (Date or DateTime)
    - to_date: End date (Date or DateTime)

  ## Returns
    %{
      total_requests: integer,
      successful_requests: integer,
      failed_requests: integer,
      total_input_tokens: integer,
      total_output_tokens: integer,
      total_cost_cents: integer,
      avg_latency_ms: float
    }
  """
  @spec totals(Date.t() | DateTime.t(), Date.t() | DateTime.t()) :: map()
  def totals(from_date, to_date) do
    from_datetime = to_datetime(from_date, :start)
    to_datetime = to_datetime(to_date, :end)

    query =
      from l in ApiUsageLog,
        where: l.inserted_at >= ^from_datetime and l.inserted_at <= ^to_datetime,
        select: %{
          total_requests: count(l.id),
          successful_requests: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", l.success)),
          failed_requests: sum(fragment("CASE WHEN ? THEN 0 ELSE 1 END", l.success)),
          total_input_tokens: coalesce(sum(l.input_tokens), 0),
          total_output_tokens: coalesce(sum(l.output_tokens), 0),
          total_cost_cents: coalesce(sum(l.estimated_cost_cents), 0),
          avg_latency_ms: coalesce(avg(l.latency_ms), 0.0)
        }

    result = Repo.one(query)

    %{
      total_requests: result.total_requests || 0,
      successful_requests: result.successful_requests || 0,
      failed_requests: result.failed_requests || 0,
      total_input_tokens: result.total_input_tokens || 0,
      total_output_tokens: result.total_output_tokens || 0,
      total_cost_cents: result.total_cost_cents || 0,
      avg_latency_ms: Float.round((result.avg_latency_ms || 0.0) * 1.0, 2)
    }
  end

  @doc """
  Returns stats grouped by provider for the given date range.

  ## Returns
    [%{provider: string, ...stats...}, ...]
  """
  @spec by_provider(Date.t() | DateTime.t(), Date.t() | DateTime.t()) :: [map()]
  def by_provider(from_date, to_date) do
    from_datetime = to_datetime(from_date, :start)
    to_datetime = to_datetime(to_date, :end)

    query =
      from l in ApiUsageLog,
        where: l.inserted_at >= ^from_datetime and l.inserted_at <= ^to_datetime,
        group_by: l.provider,
        select: %{
          provider: l.provider,
          total_requests: count(l.id),
          successful_requests: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", l.success)),
          failed_requests: sum(fragment("CASE WHEN ? THEN 0 ELSE 1 END", l.success)),
          total_input_tokens: coalesce(sum(l.input_tokens), 0),
          total_output_tokens: coalesce(sum(l.output_tokens), 0),
          total_cost_cents: coalesce(sum(l.estimated_cost_cents), 0),
          avg_latency_ms: coalesce(avg(l.latency_ms), 0.0)
        },
        order_by: [desc: count(l.id)]

    Repo.all(query)
    |> Enum.map(fn row ->
      %{
        provider: row.provider,
        total_requests: row.total_requests || 0,
        successful_requests: row.successful_requests || 0,
        failed_requests: row.failed_requests || 0,
        total_input_tokens: row.total_input_tokens || 0,
        total_output_tokens: row.total_output_tokens || 0,
        total_cost_cents: row.total_cost_cents || 0,
        avg_latency_ms: Float.round((row.avg_latency_ms || 0.0) * 1.0, 2)
      }
    end)
  end

  @doc """
  Returns daily breakdown of stats for the given date range.

  ## Returns
    [%{date: Date.t(), ...stats...}, ...]
  """
  @spec by_day(Date.t() | DateTime.t(), Date.t() | DateTime.t()) :: [map()]
  def by_day(from_date, to_date) do
    from_datetime = to_datetime(from_date, :start)
    to_datetime = to_datetime(to_date, :end)

    query =
      from l in ApiUsageLog,
        where: l.inserted_at >= ^from_datetime and l.inserted_at <= ^to_datetime,
        group_by: fragment("DATE(?)", l.inserted_at),
        select: %{
          date: fragment("DATE(?)", l.inserted_at),
          total_requests: count(l.id),
          successful_requests: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", l.success)),
          failed_requests: sum(fragment("CASE WHEN ? THEN 0 ELSE 1 END", l.success)),
          total_input_tokens: coalesce(sum(l.input_tokens), 0),
          total_output_tokens: coalesce(sum(l.output_tokens), 0),
          total_cost_cents: coalesce(sum(l.estimated_cost_cents), 0),
          avg_latency_ms: coalesce(avg(l.latency_ms), 0.0)
        },
        order_by: [asc: fragment("DATE(?)", l.inserted_at)]

    Repo.all(query)
    |> Enum.map(fn row ->
      %{
        date: row.date,
        total_requests: row.total_requests || 0,
        successful_requests: row.successful_requests || 0,
        failed_requests: row.failed_requests || 0,
        total_input_tokens: row.total_input_tokens || 0,
        total_output_tokens: row.total_output_tokens || 0,
        total_cost_cents: row.total_cost_cents || 0,
        avg_latency_ms: Float.round((row.avg_latency_ms || 0.0) * 1.0, 2)
      }
    end)
  end

  @doc """
  Returns stats grouped by model for a specific provider.
  """
  @spec by_model(String.t(), Date.t() | DateTime.t(), Date.t() | DateTime.t()) :: [map()]
  def by_model(provider, from_date, to_date) do
    from_datetime = to_datetime(from_date, :start)
    to_datetime = to_datetime(to_date, :end)

    query =
      from l in ApiUsageLog,
        where:
          l.inserted_at >= ^from_datetime and
            l.inserted_at <= ^to_datetime and
            l.provider == ^provider,
        group_by: l.model,
        select: %{
          model: l.model,
          total_requests: count(l.id),
          total_input_tokens: coalesce(sum(l.input_tokens), 0),
          total_output_tokens: coalesce(sum(l.output_tokens), 0),
          total_cost_cents: coalesce(sum(l.estimated_cost_cents), 0)
        },
        order_by: [desc: count(l.id)]

    Repo.all(query)
    |> Enum.map(fn row ->
      %{
        model: row.model,
        total_requests: row.total_requests || 0,
        total_input_tokens: row.total_input_tokens || 0,
        total_output_tokens: row.total_output_tokens || 0,
        total_cost_cents: row.total_cost_cents || 0
      }
    end)
  end

  @doc """
  Returns a list of all providers that have logged requests.
  """
  @spec list_providers() :: [String.t()]
  def list_providers do
    query =
      from l in ApiUsageLog,
        distinct: true,
        select: l.provider,
        order_by: l.provider

    Repo.all(query)
  end

  # Private helpers

  defp to_datetime(%DateTime{} = dt, _), do: dt
  defp to_datetime(%Date{} = date, :start), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
  defp to_datetime(%Date{} = date, :end), do: DateTime.new!(date, ~T[23:59:59], "Etc/UTC")
end
