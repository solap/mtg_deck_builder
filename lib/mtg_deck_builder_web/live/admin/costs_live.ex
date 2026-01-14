defmodule MtgDeckBuilderWeb.Admin.CostsLive do
  use MtgDeckBuilderWeb, :live_view

  alias MtgDeckBuilder.AI.CostStats

  @impl true
  def mount(_params, _session, socket) do
    # Default to last 30 days
    to_date = Date.utc_today()
    from_date = Date.add(to_date, -30)

    providers = CostStats.list_providers()

    {:ok,
     socket
     |> assign(:from_date, from_date)
     |> assign(:to_date, to_date)
     |> assign(:provider_filter, nil)
     |> assign(:providers, providers)
     |> assign(:page_title, "API Costs Dashboard")
     |> load_stats()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    from_date = parse_date(params["from_date"], socket.assigns.from_date)
    to_date = parse_date(params["to_date"], socket.assigns.to_date)

    provider_filter =
      case params["provider"] do
        "" -> nil
        "all" -> nil
        provider -> provider
      end

    {:noreply,
     socket
     |> assign(:from_date, from_date)
     |> assign(:to_date, to_date)
     |> assign(:provider_filter, provider_filter)
     |> load_stats()}
  end

  defp load_stats(socket) do
    from_date = socket.assigns.from_date
    to_date = socket.assigns.to_date

    totals = CostStats.totals(from_date, to_date)
    by_provider = CostStats.by_provider(from_date, to_date)
    by_day = CostStats.by_day(from_date, to_date)

    socket
    |> assign(:totals, totals)
    |> assign(:by_provider, by_provider)
    |> assign(:by_day, by_day)
  end

  defp parse_date(nil, default), do: default
  defp parse_date("", default), do: default

  defp parse_date(date_string, default) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> default
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-6">
      <div class="mb-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold text-amber-400">API Costs Dashboard</h1>
            <p class="text-slate-400 text-sm mt-1">Monitor AI API usage and costs</p>
          </div>
          <div class="flex items-center gap-4">
            <a
              href="/admin/settings"
              class="text-sm text-slate-400 hover:text-amber-400"
            >
              ⚙ Settings
            </a>
            <a
              href="/"
              class="text-sm text-slate-400 hover:text-amber-400"
            >
              ← Back to Deck
            </a>
          </div>
        </div>
      </div>

      <!-- Filters -->
      <div class="bg-slate-800 rounded-lg p-4 border border-slate-700 mb-6">
        <form phx-change="filter" class="flex flex-wrap gap-4 items-end">
          <div>
            <label class="block text-sm text-slate-400 mb-1">From Date</label>
            <input
              type="date"
              name="from_date"
              value={Date.to_iso8601(@from_date)}
              class="bg-slate-700 border border-slate-600 rounded-lg px-3 py-2 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
            />
          </div>

          <div>
            <label class="block text-sm text-slate-400 mb-1">To Date</label>
            <input
              type="date"
              name="to_date"
              value={Date.to_iso8601(@to_date)}
              class="bg-slate-700 border border-slate-600 rounded-lg px-3 py-2 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
            />
          </div>

          <div>
            <label class="block text-sm text-slate-400 mb-1">Provider</label>
            <select
              name="provider"
              class="bg-slate-700 border border-slate-600 rounded-lg px-3 py-2 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
            >
              <option value="all" selected={is_nil(@provider_filter)}>All Providers</option>
              <%= for provider <- @providers do %>
                <option value={provider} selected={@provider_filter == provider}>
                  {String.capitalize(provider)}
                </option>
              <% end %>
            </select>
          </div>
        </form>
      </div>

      <!-- Summary Cards -->
      <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6">
        <.stat_card title="Total Requests" value={@totals.total_requests} />
        <.stat_card
          title="Success Rate"
          value={format_percentage(@totals.successful_requests, @totals.total_requests)}
          color="green"
        />
        <.stat_card
          title="Total Cost"
          value={format_cost(@totals.total_cost_cents)}
          color="amber"
        />
        <.stat_card
          title="Avg Latency"
          value={"#{@totals.avg_latency_ms}ms"}
        />
      </div>

      <!-- Token Usage -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <.stat_card title="Input Tokens" value={format_number(@totals.total_input_tokens)} />
        <.stat_card title="Output Tokens" value={format_number(@totals.total_output_tokens)} />
      </div>

      <!-- Provider Breakdown -->
      <div class="bg-slate-800 rounded-lg border border-slate-700 mb-6">
        <div class="p-4 border-b border-slate-700">
          <h2 class="text-lg font-semibold text-amber-400">By Provider</h2>
        </div>
        <div class="p-4">
          <%= if Enum.empty?(@by_provider) do %>
            <p class="text-slate-500 text-center py-4">No data available for this period</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="text-slate-400 text-left">
                    <th class="pb-2 pr-4">Provider</th>
                    <th class="pb-2 pr-4 text-right">Requests</th>
                    <th class="pb-2 pr-4 text-right">Success</th>
                    <th class="pb-2 pr-4 text-right">Input Tokens</th>
                    <th class="pb-2 pr-4 text-right">Output Tokens</th>
                    <th class="pb-2 pr-4 text-right">Cost</th>
                    <th class="pb-2 text-right">Avg Latency</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for row <- @by_provider do %>
                    <tr class="border-t border-slate-700 text-slate-300">
                      <td class="py-2 pr-4 font-medium">{String.capitalize(row.provider)}</td>
                      <td class="py-2 pr-4 text-right">{format_number(row.total_requests)}</td>
                      <td class="py-2 pr-4 text-right text-green-400">
                        {format_percentage(row.successful_requests, row.total_requests)}
                      </td>
                      <td class="py-2 pr-4 text-right">{format_number(row.total_input_tokens)}</td>
                      <td class="py-2 pr-4 text-right">{format_number(row.total_output_tokens)}</td>
                      <td class="py-2 pr-4 text-right text-amber-400">
                        {format_cost(row.total_cost_cents)}
                      </td>
                      <td class="py-2 text-right">{row.avg_latency_ms}ms</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Daily Breakdown -->
      <div class="bg-slate-800 rounded-lg border border-slate-700">
        <div class="p-4 border-b border-slate-700">
          <h2 class="text-lg font-semibold text-amber-400">Daily Breakdown</h2>
        </div>
        <div class="p-4">
          <%= if Enum.empty?(@by_day) do %>
            <p class="text-slate-500 text-center py-4">No data available for this period</p>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full text-sm">
                <thead>
                  <tr class="text-slate-400 text-left">
                    <th class="pb-2 pr-4">Date</th>
                    <th class="pb-2 pr-4 text-right">Requests</th>
                    <th class="pb-2 pr-4 text-right">Success</th>
                    <th class="pb-2 pr-4 text-right">Input Tokens</th>
                    <th class="pb-2 pr-4 text-right">Output Tokens</th>
                    <th class="pb-2 pr-4 text-right">Cost</th>
                    <th class="pb-2 text-right">Avg Latency</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for row <- @by_day do %>
                    <tr class="border-t border-slate-700 text-slate-300">
                      <td class="py-2 pr-4 font-medium">{row.date}</td>
                      <td class="py-2 pr-4 text-right">{format_number(row.total_requests)}</td>
                      <td class="py-2 pr-4 text-right text-green-400">
                        {format_percentage(row.successful_requests, row.total_requests)}
                      </td>
                      <td class="py-2 pr-4 text-right">{format_number(row.total_input_tokens)}</td>
                      <td class="py-2 pr-4 text-right">{format_number(row.total_output_tokens)}</td>
                      <td class="py-2 pr-4 text-right text-amber-400">
                        {format_cost(row.total_cost_cents)}
                      </td>
                      <td class="py-2 text-right">{row.avg_latency_ms}ms</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :color, :string, default: "slate"

  defp stat_card(assigns) do
    color_class =
      case assigns.color do
        "green" -> "text-green-400"
        "amber" -> "text-amber-400"
        "red" -> "text-red-400"
        _ -> "text-slate-100"
      end

    assigns = assign(assigns, :color_class, color_class)

    ~H"""
    <div class="bg-slate-800 rounded-lg p-4 border border-slate-700">
      <h3 class="text-sm text-slate-400 mb-1">{@title}</h3>
      <p class={"text-2xl font-bold #{@color_class}"}>{@value}</p>
    </div>
    """
  end

  # Cost is stored in micro-dollars (1/1,000,000 of a dollar)
  defp format_cost(micro_dollars) when is_integer(micro_dollars) do
    dollars = micro_dollars / 1_000_000

    if dollars < 0.01 and dollars > 0 do
      # Show more precision for very small amounts
      "$#{:erlang.float_to_binary(dollars, decimals: 6)}"
    else
      "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
    end
  end

  defp format_cost(_), do: "$0.00"

  defp format_percentage(_, 0), do: "N/A"

  defp format_percentage(success, total) when is_integer(success) and is_integer(total) do
    percentage = success / total * 100
    "#{:erlang.float_to_binary(percentage, decimals: 1)}%"
  end

  defp format_percentage(_, _), do: "N/A"

  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(_), do: "0"
end
