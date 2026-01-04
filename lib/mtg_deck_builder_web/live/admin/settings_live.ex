defmodule MtgDeckBuilderWeb.Admin.SettingsLive do
  use MtgDeckBuilderWeb, :live_view

  alias MtgDeckBuilder.Settings

  @impl true
  def mount(_params, _session, socket) do
    providers = Settings.available_providers()
    settings = Settings.get_all_settings()

    {:ok,
     socket
     |> assign(:page_title, "AI Settings")
     |> assign(:providers, providers)
     |> assign(:settings, settings)
     |> assign(:active_provider, settings.active_provider)
     |> assign(:flash_message, nil)
     |> assign(:editing_key, nil)}
  end

  @impl true
  def handle_event("select_provider", %{"provider" => provider}, socket) do
    case Settings.set_active_provider(provider) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:active_provider, provider)
         |> assign(:settings, Settings.get_all_settings())
         |> put_flash(:info, "Active provider updated to #{provider_name(provider)}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update provider")}
    end
  end

  def handle_event("save_api_key", %{"provider" => provider, "api_key" => api_key}, socket) do
    api_key = String.trim(api_key)

    if api_key == "" do
      {:noreply, put_flash(socket, :error, "API key cannot be empty")}
    else
      case Settings.set_api_key(provider, api_key) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:settings, Settings.get_all_settings())
           |> assign(:editing_key, nil)
           |> put_flash(:info, "API key saved for #{provider_name(provider)}")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to save API key")}
      end
    end
  end

  def handle_event("save_model", %{"provider" => provider, "model" => model}, socket) do
    case Settings.set_model(provider, model) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:settings, Settings.get_all_settings())
         |> put_flash(:info, "Model updated for #{provider_name(provider)}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update model")}
    end
  end

  def handle_event("edit_key", %{"provider" => provider}, socket) do
    {:noreply, assign(socket, :editing_key, provider)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing_key, nil)}
  end

  defp provider_name("anthropic"), do: "Anthropic Claude"
  defp provider_name("openai"), do: "OpenAI"
  defp provider_name("xai"), do: "xAI Grok"
  defp provider_name(p), do: p

  @impl true
  def render(assigns) do
    ~H"""
    <div class="px-4 py-6 max-w-4xl mx-auto">
      <div class="mb-6">
        <div class="flex items-center justify-between">
          <div>
            <h1 class="text-2xl font-bold text-amber-400">AI Settings</h1>
            <p class="text-slate-400 text-sm mt-1">Configure AI providers and API keys</p>
          </div>
          <div class="flex items-center gap-4">
            <a
              href="/admin/costs"
              class="text-sm text-slate-400 hover:text-amber-400"
            >
              View Usage & Costs →
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

      <!-- Active Provider Selection -->
      <div class="bg-slate-800 rounded-lg p-6 border border-slate-700 mb-6">
        <h2 class="text-lg font-semibold text-amber-400 mb-4">Active Provider</h2>
        <p class="text-slate-400 text-sm mb-4">
          Select which AI service to use for chat commands.
        </p>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
          <%= for provider <- @providers do %>
            <button
              type="button"
              phx-click="select_provider"
              phx-value-provider={provider.id}
              class={[
                "p-4 rounded-lg border-2 text-left transition-all",
                if(@active_provider == provider.id,
                  do: "border-amber-400 bg-amber-400/10",
                  else: "border-slate-600 hover:border-slate-500 bg-slate-900"
                )
              ]}
            >
              <div class="flex items-center justify-between mb-2">
                <span class="font-medium text-slate-100">{provider.name}</span>
                <%= if @active_provider == provider.id do %>
                  <span class="text-amber-400 text-sm">Active</span>
                <% end %>
              </div>
              <div class="text-xs text-slate-500">
                <%= if provider_has_key?(@settings, provider.id) do %>
                  <span class="text-green-400">API key configured</span>
                <% else %>
                  <span class="text-red-400">No API key</span>
                <% end %>
              </div>
            </button>
          <% end %>
        </div>
      </div>

      <!-- Provider Configurations -->
      <%= for provider <- @providers do %>
        <.provider_config
          provider={provider}
          settings={@settings}
          active={@active_provider == provider.id}
          editing_key={@editing_key}
        />
      <% end %>

      <!-- Sample Deck -->
      <div class="bg-slate-800 rounded-lg p-6 border border-slate-700 mt-6">
        <h2 class="text-lg font-semibold text-amber-400 mb-4">Sample Deck</h2>
        <p class="text-slate-400 text-sm mb-4">
          Load a pre-built 4c Reanimator deck to test AI chat commands.
        </p>
        <a
          href="/?load_sample=true"
          class="inline-block bg-amber-500 hover:bg-amber-600 text-slate-900 font-medium px-4 py-2 rounded-lg"
        >
          Load Sample Deck
        </a>
      </div>

      <!-- Help Text -->
      <div class="bg-slate-900 rounded-lg p-4 border border-slate-700 mt-6">
        <h3 class="text-sm font-medium text-slate-400 mb-2">Getting API Keys</h3>
        <ul class="text-sm text-slate-500 space-y-1">
          <li>
            <span class="text-slate-400">Anthropic:</span>
            <a
              href="https://console.anthropic.com/settings/keys"
              target="_blank"
              class="text-amber-400 hover:underline"
            >
              console.anthropic.com/settings/keys
            </a>
          </li>
          <li>
            <span class="text-slate-400">OpenAI:</span>
            <a
              href="https://platform.openai.com/api-keys"
              target="_blank"
              class="text-amber-400 hover:underline"
            >
              platform.openai.com/api-keys
            </a>
          </li>
          <li>
            <span class="text-slate-400">xAI:</span>
            <a
              href="https://console.x.ai"
              target="_blank"
              class="text-amber-400 hover:underline"
            >
              console.x.ai
            </a>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :provider, :map, required: true
  attr :settings, :map, required: true
  attr :active, :boolean, required: true
  attr :editing_key, :string, required: true

  defp provider_config(assigns) do
    provider_settings = Map.get(assigns.settings, String.to_atom(assigns.provider.id), %{})
    assigns = assign(assigns, :provider_settings, provider_settings)

    ~H"""
    <div class={[
      "bg-slate-800 rounded-lg p-6 border mb-4",
      if(@active, do: "border-amber-400/50", else: "border-slate-700")
    ]}>
      <div class="flex items-center justify-between mb-4">
        <h2 class="text-lg font-semibold text-slate-100">{@provider.name}</h2>
        <%= if @active do %>
          <span class="bg-amber-400/20 text-amber-400 text-xs px-2 py-1 rounded">Active</span>
        <% end %>
      </div>

      <!-- API Key Section -->
      <div class="mb-4">
        <label class="block text-sm text-slate-400 mb-2">API Key</label>
        <%= if @editing_key == @provider.id do %>
          <form phx-submit="save_api_key" class="flex gap-2">
            <input type="hidden" name="provider" value={@provider.id} />
            <input
              type="password"
              name="api_key"
              placeholder="Enter API key..."
              autocomplete="off"
              class="flex-1 bg-slate-700 border border-slate-600 rounded-lg px-3 py-2 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
            />
            <button
              type="submit"
              class="bg-amber-500 hover:bg-amber-600 text-slate-900 font-medium px-4 py-2 rounded-lg"
            >
              Save
            </button>
            <button
              type="button"
              phx-click="cancel_edit"
              class="bg-slate-600 hover:bg-slate-500 text-slate-100 px-4 py-2 rounded-lg"
            >
              Cancel
            </button>
          </form>
        <% else %>
          <div class="flex items-center gap-2">
            <%= if @provider_settings[:has_key] do %>
              <span class="bg-slate-700 rounded-lg px-3 py-2 text-slate-400 flex-1">
                ••••••••••••••••
              </span>
            <% else %>
              <span class="bg-slate-700 rounded-lg px-3 py-2 text-slate-500 flex-1 italic">
                Not configured
              </span>
            <% end %>
            <button
              type="button"
              phx-click="edit_key"
              phx-value-provider={@provider.id}
              class="bg-slate-600 hover:bg-slate-500 text-slate-100 px-4 py-2 rounded-lg text-sm"
            >
              {if @provider_settings[:has_key], do: "Update", else: "Add Key"}
            </button>
          </div>
        <% end %>
      </div>

      <!-- Model Selection -->
      <div>
        <label class="block text-sm text-slate-400 mb-2">Model</label>
        <form phx-change="save_model">
          <input type="hidden" name="provider" value={@provider.id} />
          <select
            name="model"
            class="w-full bg-slate-700 border border-slate-600 rounded-lg px-3 py-2 text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
          >
            <%= for model <- @provider.models do %>
              <option value={model.id} selected={@provider_settings[:model] == model.id}>
                {model.name}
              </option>
            <% end %>
          </select>
        </form>
      </div>
    </div>
    """
  end

  defp provider_has_key?(settings, "anthropic"), do: settings.anthropic.has_key
  defp provider_has_key?(settings, "openai"), do: settings.openai.has_key
  defp provider_has_key?(settings, "xai"), do: settings.xai.has_key
  defp provider_has_key?(_, _), do: false
end
