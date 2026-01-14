defmodule MtgDeckBuilderWeb.Admin.ProvidersLive do
  @moduledoc """
  LiveView for managing AI provider configurations and API keys.
  """
  use MtgDeckBuilderWeb, :live_view

  alias MtgDeckBuilder.AI.{AgentRegistry, KeyVerifier}

  @impl true
  def mount(_params, _session, socket) do
    providers = AgentRegistry.list_provider_statuses()

    {:ok,
     assign(socket,
       page_title: "AI Providers",
       providers: providers,
       editing_provider: nil,
       api_key_input: "",
       verifying: nil,
       flash_message: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-slate-900 text-slate-100 p-6">
      <div class="max-w-4xl mx-auto">
        <div class="flex items-center justify-between mb-6">
          <h1 class="text-2xl font-bold text-amber-400">AI Providers</h1>
          <a
            href="/admin/agents"
            class="text-sm text-slate-400 hover:text-amber-400"
          >
            &larr; Back to Agents
          </a>
        </div>

        <%= if @flash_message do %>
          <div class={[
            "mb-4 p-3 rounded-lg text-sm",
            if(@flash_message.type == :success, do: "bg-green-900/50 text-green-300", else: "bg-red-900/50 text-red-300")
          ]}>
            {@flash_message.message}
          </div>
        <% end %>

        <div class="space-y-4">
          <%= for provider <- @providers do %>
            <div class="bg-slate-800 rounded-lg border border-slate-700 p-4">
              <div class="flex items-start justify-between">
                <div class="flex-1">
                  <div class="flex items-center gap-3 mb-2">
                    <h2 class="text-lg font-semibold capitalize">{provider.provider}</h2>
                    <.status_badge status={provider.key_status} />
                    <%= if provider.key_source != :none do %>
                      <span class="text-xs text-slate-500 bg-slate-700 px-2 py-0.5 rounded">
                        {format_key_source(provider.key_source)}
                      </span>
                    <% end %>
                  </div>

                  <div class="text-sm text-slate-400 space-y-1">
                    <%= if provider.last_verified_at do %>
                      <p>Last verified: {format_datetime(provider.last_verified_at)}</p>
                    <% end %>
                    <%= if provider.last_error do %>
                      <p class="text-red-400">Error: {provider.last_error}</p>
                    <% end %>
                  </div>
                </div>

                <div class="flex items-center gap-2">
                  <%= if @verifying == provider.provider do %>
                    <span class="text-sm text-slate-400 animate-pulse">Verifying...</span>
                  <% else %>
                    <%= if provider.has_key do %>
                      <button
                        type="button"
                        phx-click="verify_key"
                        phx-value-provider={provider.provider}
                        class="px-3 py-1.5 text-sm bg-slate-700 hover:bg-slate-600 rounded"
                      >
                        Test Key
                      </button>
                    <% end %>
                    <button
                      type="button"
                      phx-click="edit_provider"
                      phx-value-provider={provider.provider}
                      class="px-3 py-1.5 text-sm bg-amber-500 hover:bg-amber-400 text-slate-900 rounded font-medium"
                    >
                      {if provider.has_key, do: "Change Key", else: "Add Key"}
                    </button>
                  <% end %>
                </div>
              </div>

              <!-- Edit form -->
              <%= if @editing_provider == provider.provider do %>
                <form phx-submit="save_key" class="mt-4 pt-4 border-t border-slate-700">
                  <input type="hidden" name="provider" value={provider.provider} />

                  <div class="mb-3">
                    <label class="block text-sm font-medium text-slate-400 mb-1">
                      API Key
                    </label>
                    <input
                      type="password"
                      name="api_key"
                      value={@api_key_input}
                      placeholder="Enter API key..."
                      autocomplete="off"
                      class="w-full bg-slate-700 border border-slate-600 rounded px-3 py-2 text-sm text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-400"
                    />
                    <p class="mt-1 text-xs text-slate-500">
                      Key will be encrypted before storage. Leave blank and save to use environment variable only.
                    </p>
                  </div>

                  <div class="flex items-center justify-between">
                    <div class="flex gap-2">
                      <button
                        type="submit"
                        class="px-4 py-2 text-sm bg-amber-500 hover:bg-amber-400 text-slate-900 rounded font-medium"
                      >
                        Save Key
                      </button>
                      <button
                        type="button"
                        phx-click="cancel_edit"
                        class="px-4 py-2 text-sm text-slate-400 hover:text-slate-300"
                      >
                        Cancel
                      </button>
                    </div>

                    <%= if provider.key_source == :database do %>
                      <button
                        type="button"
                        phx-click="clear_key"
                        phx-value-provider={provider.provider}
                        class="px-3 py-1.5 text-sm text-red-400 hover:text-red-300 hover:bg-red-900/20 rounded"
                      >
                        Clear DB Key
                      </button>
                    <% end %>
                  </div>
                </form>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="mt-8 p-4 bg-slate-800/50 rounded-lg border border-slate-700">
          <h3 class="text-sm font-medium text-slate-300 mb-2">Key Resolution Order</h3>
          <ol class="text-sm text-slate-400 list-decimal list-inside space-y-1">
            <li>Database key (encrypted, set via this UI)</li>
            <li>Environment variable (e.g., ANTHROPIC_API_KEY)</li>
          </ol>
          <p class="mt-2 text-xs text-slate-500">
            Database keys take priority. Clear them to fall back to environment variables.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp status_badge(assigns) do
    {bg, text} =
      case assigns.status do
        "valid" -> {"bg-green-900/50", "text-green-400"}
        "invalid" -> {"bg-red-900/50", "text-red-400"}
        "configured" -> {"bg-yellow-900/50", "text-yellow-400"}
        _ -> {"bg-slate-700", "text-slate-400"}
      end

    assigns = assign(assigns, bg: bg, text: text)

    ~H"""
    <span class={["text-xs px-2 py-0.5 rounded", @bg, @text]}>
      {format_status(@status)}
    </span>
    """
  end

  defp format_status("not_configured"), do: "Not Configured"
  defp format_status("configured"), do: "Configured"
  defp format_status("valid"), do: "Valid"
  defp format_status("invalid"), do: "Invalid"
  defp format_status(status), do: status

  defp format_key_source(:database), do: "DB"
  defp format_key_source(:environment), do: "ENV"
  defp format_key_source(_), do: ""

  defp format_datetime(nil), do: "Never"

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  @impl true
  def handle_event("edit_provider", %{"provider" => provider}, socket) do
    {:noreply, assign(socket, editing_provider: provider, api_key_input: "", flash_message: nil)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editing_provider: nil, api_key_input: "")}
  end

  @impl true
  def handle_event("save_key", %{"provider" => provider, "api_key" => api_key}, socket) do
    result =
      if api_key == "" do
        # Clear DB key, fall back to env
        AgentRegistry.clear_provider_api_key(provider)
      else
        AgentRegistry.set_provider_api_key(provider, api_key)
      end

    case result do
      {:ok, _config} ->
        providers = AgentRegistry.list_provider_statuses()

        {:noreply,
         assign(socket,
           providers: providers,
           editing_provider: nil,
           api_key_input: "",
           flash_message: %{type: :success, message: "API key updated for #{provider}"}
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           flash_message: %{type: :error, message: "Failed to save: #{inspect(reason)}"}
         )}
    end
  end

  @impl true
  def handle_event("clear_key", %{"provider" => provider}, socket) do
    case AgentRegistry.clear_provider_api_key(provider) do
      {:ok, _config} ->
        providers = AgentRegistry.list_provider_statuses()

        {:noreply,
         assign(socket,
           providers: providers,
           editing_provider: nil,
           flash_message: %{type: :success, message: "Database key cleared for #{provider}"}
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           flash_message: %{type: :error, message: "Failed to clear: #{inspect(reason)}"}
         )}
    end
  end

  @impl true
  def handle_event("verify_key", %{"provider" => provider}, socket) do
    # Start verification in background
    send(self(), {:verify_key, provider})
    {:noreply, assign(socket, verifying: provider, flash_message: nil)}
  end

  @impl true
  def handle_info({:verify_key, provider}, socket) do
    result = KeyVerifier.verify_and_update(provider)

    providers = AgentRegistry.list_provider_statuses()

    flash =
      case result do
        {:ok, :valid} ->
          %{type: :success, message: "#{provider} API key is valid!"}

        {:error, reason} ->
          %{type: :error, message: "#{provider} verification failed: #{reason}"}
      end

    {:noreply,
     assign(socket,
       providers: providers,
       verifying: nil,
       flash_message: flash
     )}
  end
end
