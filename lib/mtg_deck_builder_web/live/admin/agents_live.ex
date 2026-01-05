defmodule MtgDeckBuilderWeb.Admin.AgentsLive do
  @moduledoc """
  LiveView for managing AI agent configurations.

  Provides a UI for:
  - Viewing all configured agents
  - Editing agent system prompts
  - Changing agent models and parameters
  - Previewing formatted requests
  """

  use MtgDeckBuilderWeb, :live_view

  alias MtgDeckBuilder.AI.{AgentRegistry, ModelRegistry}

  @impl true
  def mount(_params, _session, socket) do
    agents = AgentRegistry.list_agents()
    provider_statuses = AgentRegistry.list_provider_statuses() |> Map.new(&{&1.provider, &1})
    models_by_provider = ModelRegistry.models_by_provider()

    socket =
      socket
      |> assign(:page_title, "Agent Configuration")
      |> assign(:agents, agents)
      |> assign(:provider_statuses, provider_statuses)
      |> assign(:models_by_provider, models_by_provider)
      |> assign(:selected_agent_id, nil)
      |> assign(:editing, false)
      |> assign(:preview, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(%{"agent_id" => agent_id}, _uri, socket) do
    agent = AgentRegistry.get_agent(agent_id)

    if agent do
      {:noreply,
       socket
       |> assign(:selected_agent_id, agent_id)
       |> assign(:selected_agent, agent)
       |> assign(:editing, false)
       |> assign(:preview, nil)}
    else
      {:noreply, push_navigate(socket, to: ~p"/admin/agents")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:selected_agent_id, nil)
     |> assign(:selected_agent, nil)
     |> assign(:editing, false)
     |> assign(:preview, nil)}
  end

  @impl true
  def handle_event("toggle_agent", %{"agent_id" => agent_id}, socket) do
    # Toggle expansion - if same agent, collapse; otherwise expand new one
    new_selected =
      if socket.assigns.selected_agent_id == agent_id do
        nil
      else
        agent_id
      end

    agent = if new_selected, do: AgentRegistry.get_agent(new_selected), else: nil

    {:noreply,
     socket
     |> assign(:selected_agent_id, new_selected)
     |> assign(:selected_agent, agent)
     |> assign(:editing, false)
     |> assign(:preview, nil)}
  end

  def handle_event("start_edit", _params, socket) do
    {:noreply, assign(socket, :editing, true)}
  end

  def handle_event("model_changed", %{"model" => model_id}, socket) do
    # Update the selected agent's model (in-memory only for preview)
    # Also update the provider based on the model
    model = ModelRegistry.get_model(model_id)
    updated_agent = %{socket.assigns.selected_agent | model: model_id}

    updated_agent =
      if model do
        %{updated_agent | provider: model.provider}
      else
        updated_agent
      end

    {:noreply, assign(socket, :selected_agent, updated_agent)}
  end

  def handle_event("cancel_edit", _params, socket) do
    # Reload the agent to discard changes
    agent = AgentRegistry.get_agent(socket.assigns.selected_agent_id)
    {:noreply,
     socket
     |> assign(:selected_agent, agent)
     |> assign(:editing, false)}
  end

  def handle_event("save_agent", params, socket) do
    # Get provider from the model
    model_id = params["model"]
    model_info = ModelRegistry.get_model(model_id)
    provider = if model_info, do: model_info.provider, else: socket.assigns.selected_agent.provider

    updates = %{
      system_prompt: params["system_prompt"],
      model: model_id,
      provider: provider,
      temperature: parse_temperature(params["temperature"]),
      max_tokens: parse_integer(params["max_tokens"])
    }

    case AgentRegistry.update_agent(socket.assigns.selected_agent_id, updates) do
      {:ok, updated_agent} ->
        {:noreply,
         socket
         |> assign(:selected_agent, updated_agent)
         |> assign(:agents, AgentRegistry.list_agents())
         |> assign(:editing, false)
         |> put_flash(:info, "Agent updated successfully")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update agent: #{reason}")}
    end
  end

  def handle_event("reset_prompt", _params, socket) do
    case AgentRegistry.reset_agent_prompt(socket.assigns.selected_agent_id) do
      {:ok, updated_agent} ->
        {:noreply,
         socket
         |> assign(:selected_agent, updated_agent)
         |> put_flash(:info, "System prompt reset to default")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to reset prompt: #{reason}")}
    end
  end

  def handle_event("preview_request", _params, socket) do
    agent = socket.assigns.selected_agent
    adapter = MtgDeckBuilder.AI.ProviderAdapter.get_adapter(agent.provider)

    sample_context = """
    Deck: UW Control (Modern)
    Archetype: Control
    Key Cards: Teferi, Hero of Dominaria; Supreme Verdict
    Theme: Planeswalker-based control with counterspells

    Mainboard: 60 cards
    - 4x Teferi, Hero of Dominaria
    - 4x Supreme Verdict
    - 4x Counterspell
    ...

    User Question: What should I cut to make room for more removal?
    """

    messages = [%{role: "user", content: sample_context}]
    opts = %{
      model: agent.model,
      max_tokens: agent.max_tokens,
      temperature: Decimal.to_float(agent.temperature)
    }

    preview =
      if adapter do
        request = adapter.format_request(agent.system_prompt, messages, opts)
        Jason.encode!(request, pretty: true)
      else
        "Provider adapter not found for: #{agent.provider}"
      end

    {:noreply, assign(socket, :preview, preview)}
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :preview, nil)}
  end

  defp parse_temperature(nil), do: nil
  defp parse_temperature(""), do: nil
  defp parse_temperature(val) when is_binary(val) do
    case Decimal.parse(val) do
      {decimal, ""} -> decimal
      _ -> nil
    end
  end
  defp parse_temperature(val), do: val

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, ""} -> int
      _ -> nil
    end
  end
  defp parse_integer(val) when is_integer(val), do: val

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-900 text-slate-100">
      <div class="max-w-4xl mx-auto px-4 py-8">
        <div class="flex items-center justify-between mb-8">
          <h1 class="text-2xl font-bold text-amber-400">Agent Configuration</h1>
          <div class="flex items-center gap-4">
            <a href="/admin/providers" class="text-slate-400 hover:text-amber-400 text-sm">
              Manage API Keys &rarr;
            </a>
            <a href="/" class="text-slate-400 hover:text-amber-400 text-sm">
              &larr; Back to Deck Builder
            </a>
          </div>
        </div>

        <!-- Agent List with Expandable Details -->
        <div class="space-y-3">
          <%= for agent <- @agents do %>
            <% provider_status = @provider_statuses[agent.provider] %>
            <% is_selected = @selected_agent_id == agent.agent_id %>
            <div class={[
              "bg-slate-800 rounded-lg border transition-colors",
              if(is_selected, do: "border-amber-500", else: "border-slate-700")
            ]}>
              <!-- Agent Header (clickable) -->
              <button
                type="button"
                phx-click="toggle_agent"
                phx-value-agent_id={agent.agent_id}
                class="w-full text-left p-4 flex items-center justify-between hover:bg-slate-750"
              >
                <div class="flex-1">
                  <div class="flex items-center gap-3">
                    <span class={[
                      "font-medium",
                      if(is_selected, do: "text-amber-400", else: "text-slate-100")
                    ]}>
                      {agent.name}
                    </span>
                    <span class={[
                      "w-2 h-2 rounded-full",
                      if(agent.enabled, do: "bg-green-400", else: "bg-red-400")
                    ]}></span>
                    <%= if provider_status do %>
                      <span class={[
                        "text-xs px-2 py-0.5 rounded",
                        case provider_status.key_status do
                          "valid" -> "bg-green-500/20 text-green-400"
                          "invalid" -> "bg-red-500/20 text-red-400"
                          "configured" -> "bg-yellow-500/20 text-yellow-400"
                          _ -> "bg-slate-700 text-slate-500"
                        end
                      ]}>
                        {format_key_status(provider_status.key_status)}
                      </span>
                    <% end %>
                  </div>
                  <div class="text-xs text-slate-400 mt-1">{agent.description}</div>
                  <div class="text-xs text-slate-500 mt-1">
                    {agent.provider} / {agent.model}
                  </div>
                </div>
                <div class={[
                  "text-slate-400 transition-transform",
                  if(is_selected, do: "rotate-180", else: "")
                ]}>
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                </div>
              </button>

              <!-- Expanded Details -->
              <%= if is_selected && @selected_agent do %>
                <div class="border-t border-slate-700 p-4">
                  <%= if @editing do %>
                    <form phx-submit="save_agent" class="space-y-4">
                      <!-- Model Selection -->
                      <div>
                        <label class="block text-sm font-medium text-slate-400 mb-2">Model</label>
                        <select
                          name="model"
                          phx-change="model_changed"
                          class="w-full bg-slate-700 border border-slate-600 rounded-lg px-4 py-2 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
                        >
                          <%= for {provider, models} <- @models_by_provider do %>
                            <optgroup label={ModelRegistry.provider_name(provider)}>
                              <%= for model <- models do %>
                                <option value={model.id} selected={@selected_agent.model == model.id}>
                                  {model.name} ({format_context_window(model.context_window)})
                                </option>
                              <% end %>
                            </optgroup>
                          <% end %>
                        </select>
                        <%= if model_info = ModelRegistry.get_model(@selected_agent.model) do %>
                          <div class="mt-2 text-xs text-slate-500">
                            Context: {format_context_window(model_info.context_window)} |
                            Max output: {format_tokens(model_info.max_output_tokens)} |
                            Tools: {if model_info.supports_tools, do: "Yes", else: "No"} |
                            Vision: {if model_info.supports_vision, do: "Yes", else: "No"}
                          </div>
                        <% end %>
                      </div>

                      <div class="grid grid-cols-2 gap-4">
                        <!-- Temperature -->
                        <div>
                          <label class="block text-sm font-medium text-slate-400 mb-2">
                            Temperature: <span id="temp-value">{Decimal.to_string(@selected_agent.temperature)}</span>
                          </label>
                          <input
                            type="range"
                            name="temperature"
                            min="0"
                            max="2"
                            step="0.1"
                            value={Decimal.to_string(@selected_agent.temperature)}
                            class="w-full h-2 bg-slate-700 rounded-lg appearance-none cursor-pointer"
                            oninput="document.getElementById('temp-value').textContent = this.value"
                          />
                        </div>

                        <!-- Max Tokens -->
                        <div>
                          <label class="block text-sm font-medium text-slate-400 mb-2">Max Tokens</label>
                          <input
                            type="number"
                            name="max_tokens"
                            value={@selected_agent.max_tokens}
                            min="100"
                            max="8000"
                            class="w-full bg-slate-700 border border-slate-600 rounded-lg px-3 py-1.5 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
                          />
                        </div>
                      </div>

                      <!-- System Prompt -->
                      <div>
                        <div class="flex items-center justify-between mb-2">
                          <label class="block text-sm font-medium text-slate-400">System Prompt</label>
                          <button
                            type="button"
                            phx-click="reset_prompt"
                            class="text-xs text-slate-500 hover:text-amber-400"
                          >
                            Reset to Default
                          </button>
                        </div>
                        <textarea
                          name="system_prompt"
                          rows="10"
                          class="w-full bg-slate-700 border border-slate-600 rounded-lg px-4 py-3 text-slate-100 font-mono text-sm focus:outline-none focus:ring-2 focus:ring-amber-400 resize-y"
                        ><%= @selected_agent.system_prompt %></textarea>
                      </div>

                      <!-- Actions -->
                      <div class="flex items-center justify-between pt-2">
                        <button
                          type="button"
                          phx-click="preview_request"
                          class="text-slate-400 hover:text-amber-400 text-sm"
                        >
                          Preview Request
                        </button>
                        <div class="flex items-center gap-3">
                          <button
                            type="button"
                            phx-click="cancel_edit"
                            class="text-slate-400 hover:text-slate-300 px-4 py-2 text-sm"
                          >
                            Cancel
                          </button>
                          <button
                            type="submit"
                            class="bg-amber-500 hover:bg-amber-400 text-slate-900 px-6 py-2 rounded font-medium text-sm"
                          >
                            Save
                          </button>
                        </div>
                      </div>
                    </form>
                  <% else %>
                    <!-- View Mode -->
                    <div class="space-y-4">
                      <div class="grid grid-cols-4 gap-4 text-sm">
                        <div>
                          <label class="block text-xs font-medium text-slate-500 mb-1">Provider</label>
                          <p class="text-slate-100 capitalize">{@selected_agent.provider}</p>
                        </div>
                        <div>
                          <label class="block text-xs font-medium text-slate-500 mb-1">Model</label>
                          <p class="text-slate-100">{@selected_agent.model}</p>
                        </div>
                        <div>
                          <label class="block text-xs font-medium text-slate-500 mb-1">Temperature</label>
                          <p class="text-slate-100">{Decimal.to_string(@selected_agent.temperature)}</p>
                        </div>
                        <div>
                          <label class="block text-xs font-medium text-slate-500 mb-1">Max Tokens</label>
                          <p class="text-slate-100">{@selected_agent.max_tokens}</p>
                        </div>
                      </div>

                      <div>
                        <label class="block text-xs font-medium text-slate-500 mb-2">System Prompt</label>
                        <div class="bg-slate-900 rounded-lg p-4 border border-slate-700 max-h-64 overflow-y-auto">
                          <pre class="text-slate-300 text-sm whitespace-pre-wrap font-mono"><%= @selected_agent.system_prompt %></pre>
                        </div>
                      </div>

                      <div class="flex items-center justify-between pt-2">
                        <%= if @selected_agent.cost_per_1k_input || @selected_agent.cost_per_1k_output do %>
                          <div class="text-xs text-slate-500">
                            Cost: ${format_cost(@selected_agent.cost_per_1k_input)}/1K in,
                            ${format_cost(@selected_agent.cost_per_1k_output)}/1K out
                          </div>
                        <% else %>
                          <div></div>
                        <% end %>
                        <button
                          type="button"
                          phx-click="start_edit"
                          class="bg-amber-500 hover:bg-amber-400 text-slate-900 px-4 py-2 rounded font-medium text-sm"
                        >
                          Edit
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Preview Modal -->
        <%= if @preview do %>
          <div class="fixed inset-0 bg-black/50 flex items-center justify-center z-50" phx-click="close_preview">
            <div class="bg-slate-800 rounded-lg border border-slate-700 max-w-4xl w-full mx-4 max-h-[80vh] overflow-auto" phx-click-away="close_preview">
              <div class="sticky top-0 bg-slate-800 p-4 border-b border-slate-700 flex items-center justify-between">
                <h3 class="text-lg font-semibold text-amber-400">Preview: Formatted Request</h3>
                <button type="button" phx-click="close_preview" class="text-slate-400 hover:text-slate-300">
                  &times;
                </button>
              </div>
              <div class="p-4">
                <pre class="bg-slate-900 rounded-lg p-4 text-sm text-slate-300 font-mono whitespace-pre-wrap overflow-auto"><%= @preview %></pre>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_cost(nil), do: "N/A"
  defp format_cost(%Decimal{} = cost), do: Decimal.to_string(cost)
  defp format_cost(cost), do: to_string(cost)

  defp format_key_status("not_configured"), do: "Missing"
  defp format_key_status("configured"), do: "Untested"
  defp format_key_status("valid"), do: "Valid"
  defp format_key_status("invalid"), do: "Invalid"
  defp format_key_status(status), do: status

  defp format_context_window(tokens) when tokens >= 1_000_000 do
    "#{div(tokens, 1_000_000)}M"
  end

  defp format_context_window(tokens) when tokens >= 1_000 do
    "#{div(tokens, 1_000)}K"
  end

  defp format_context_window(tokens), do: "#{tokens}"

  defp format_tokens(tokens) when tokens >= 1_000 do
    "#{div(tokens, 1_000)}K"
  end

  defp format_tokens(tokens), do: "#{tokens}"

  defp format_structured_output(:json_schema), do: "JSON Schema"
  defp format_structured_output(:tool_use), do: "Tool Use"
  defp format_structured_output(:json_mode), do: "JSON Mode"
  defp format_structured_output(:none), do: "None"
  defp format_structured_output(_), do: "Unknown"
end
