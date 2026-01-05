defmodule MtgDeckBuilderWeb.Components.BrewPanel do
  @moduledoc """
  Function component for the Brew Mode panel.

  Displays and allows editing of the brew's strategic context:
  - Archetype selector
  - Color selector
  - Key cards list with add/remove and present/missing status
  - Synergies textarea describing how key cards work together
  - Theme textarea with character counter

  ## Usage

      <.brew_panel
        brew={@brew}
        deck_card_names={@deck_card_names}
        brew_search_results={@brew_search_results}
        brew_search_query={@brew_search_query}
      />
  """

  use Phoenix.Component
  alias MtgDeckBuilder.Brew

  @archetypes [
    {"Select archetype...", nil},
    {"Control", "control"},
    {"Aggro", "aggro"},
    {"Midrange", "midrange"},
    {"Combo", "combo"},
    {"Tempo", "tempo"},
    {"Ramp", "ramp"}
  ]

  attr :brew, Brew, required: true
  attr :deck_card_names, :list, default: []
  attr :brew_search_results, :list, default: []
  attr :brew_search_query, :string, default: ""
  attr :collapsed, :boolean, default: false

  def brew_panel(assigns) do
    # Calculate key card statuses
    key_card_statuses =
      if assigns.brew do
        Enum.map(assigns.brew.key_cards, fn card_name ->
          present = card_present?(card_name, assigns.deck_card_names)
          {card_name, present}
        end)
      else
        []
      end

    assigns =
      assigns
      |> assign(:key_card_statuses, key_card_statuses)
      |> assign(:archetypes, @archetypes)
      |> assign(:synergies_length, String.length(assigns.brew && assigns.brew.synergies || ""))
      |> assign(:theme_length, String.length(assigns.brew && assigns.brew.theme || ""))
      |> assign(:max_theme_length, 500)

    ~H"""
    <div class="bg-slate-800 rounded-lg border border-slate-700">
      <!-- Header with collapse toggle -->
      <div
        class="p-3 border-b border-slate-700 cursor-pointer flex items-center justify-between"
        phx-click="toggle_brew_panel"
      >
        <h2 class="text-sm font-semibold text-amber-400 flex items-center gap-2">
          <span>Brew</span>
          <%= if @brew && @brew.archetype do %>
            <span class="text-xs text-slate-400 capitalize">({@brew.archetype})</span>
          <% end %>
        </h2>
        <span class="text-slate-400 text-sm">
          <%= if @collapsed, do: "+", else: "-" %>
        </span>
      </div>

      <%= unless @collapsed do %>
        <div class="p-3 space-y-4">
          <!-- Archetype Selector -->
          <div>
            <label class="block text-xs font-medium text-slate-400 mb-1">Archetype</label>
            <select
              name="archetype"
              phx-change="update_brew_archetype"
              class="w-full bg-slate-700 border border-slate-600 rounded px-3 py-2 text-sm text-slate-100 focus:outline-none focus:ring-2 focus:ring-amber-400"
            >
              <%= for {label, value} <- @archetypes do %>
                <option
                  value={value || ""}
                  selected={@brew && @brew.archetype && Atom.to_string(@brew.archetype) == value}
                >
                  {label}
                </option>
              <% end %>
            </select>
          </div>

          <!-- Colors -->
          <div>
            <label class="block text-xs font-medium text-slate-400 mb-1">Colors</label>
            <div class="flex gap-2">
              <.color_checkbox color="W" label="W" brew={@brew} bg_class="bg-amber-100" text_class="text-amber-900" />
              <.color_checkbox color="U" label="U" brew={@brew} bg_class="bg-blue-500" text_class="text-white" />
              <.color_checkbox color="B" label="B" brew={@brew} bg_class="bg-slate-900" text_class="text-slate-100" />
              <.color_checkbox color="R" label="R" brew={@brew} bg_class="bg-red-500" text_class="text-white" />
              <.color_checkbox color="G" label="G" brew={@brew} bg_class="bg-green-600" text_class="text-white" />
            </div>
          </div>

          <!-- Key Cards -->
          <div>
            <label class="block text-xs font-medium text-slate-400 mb-1">
              Key Cards ({length(@key_card_statuses)}/10)
            </label>

            <!-- Key Cards List -->
            <div class="space-y-1 mb-2">
              <%= for {card_name, present} <- @key_card_statuses do %>
                <div class="flex items-center justify-between bg-slate-700 rounded px-2 py-1">
                  <div class="flex items-center gap-2">
                    <span class={[
                      "w-2 h-2 rounded-full",
                      if(present, do: "bg-green-400", else: "bg-red-400")
                    ]}></span>
                    <span class="text-sm text-slate-100">{card_name}</span>
                  </div>
                  <button
                    type="button"
                    phx-click="remove_key_card"
                    phx-value-card={card_name}
                    class="text-slate-400 hover:text-red-400 text-sm"
                  >
                    &times;
                  </button>
                </div>
              <% end %>
            </div>

            <!-- Add Key Card Search -->
            <%= if length(@key_card_statuses) < 10 do %>
              <form phx-change="search_cards_for_brew" class="relative">
                <input
                  type="text"
                  name="brew_card_search"
                  value={@brew_search_query}
                  placeholder="Add key card..."
                  autocomplete="off"
                  phx-debounce="300"
                  class="w-full bg-slate-700 border border-slate-600 rounded px-3 py-1.5 text-sm text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-400"
                />

                <!-- Search Results Dropdown -->
                <%= if length(@brew_search_results) > 0 do %>
                  <div class="absolute z-10 w-full mt-1 bg-slate-700 border border-slate-600 rounded-lg shadow-lg max-h-40 overflow-y-auto">
                    <%= for card <- @brew_search_results do %>
                      <button
                        type="button"
                        phx-click="add_key_card"
                        phx-value-card={card.name}
                        class="w-full text-left px-3 py-2 text-sm text-slate-100 hover:bg-slate-600 border-b border-slate-600 last:border-b-0"
                      >
                        <span class="font-medium">{card.name}</span>
                        <span class="text-slate-400 text-xs ml-2">{card.mana_cost}</span>
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </form>
            <% end %>
          </div>

          <!-- Synergies Description -->
          <div>
            <label class="block text-xs font-medium text-slate-400 mb-1">
              Synergies ({@synergies_length}/300)
            </label>
            <form phx-change="update_synergies" phx-debounce="500">
              <textarea
                name="synergies"
                placeholder="Describe how your key cards work together..."
                maxlength="300"
                rows="2"
                class="w-full bg-slate-700 border border-slate-600 rounded px-3 py-2 text-sm text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-400 resize-none"
              ><%= @brew && @brew.synergies %></textarea>
            </form>
          </div>

          <!-- Theme -->
          <div>
            <label class="block text-xs font-medium text-slate-400 mb-1">
              Theme Description ({@theme_length}/{@max_theme_length})
            </label>
            <form phx-change="update_theme" phx-debounce="500">
              <textarea
                name="theme"
                placeholder="Describe your deck's strategy and identity..."
                maxlength={@max_theme_length}
                rows="3"
                class="w-full bg-slate-700 border border-slate-600 rounded px-3 py-2 text-sm text-slate-100 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-amber-400 resize-none"
              ><%= @brew && @brew.theme %></textarea>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp card_present?(card_name, deck_card_names) do
    deck_names_downcased = MapSet.new(deck_card_names, &String.downcase/1)
    MapSet.member?(deck_names_downcased, String.downcase(card_name))
  end

  attr :color, :string, required: true
  attr :label, :string, required: true
  attr :brew, Brew, required: true
  attr :bg_class, :string, required: true
  attr :text_class, :string, required: true

  defp color_checkbox(assigns) do
    selected = assigns.brew && assigns.color in (assigns.brew.colors || [])
    assigns = assign(assigns, :selected, selected)

    ~H"""
    <button
      type="button"
      phx-click="toggle_color"
      phx-value-color={@color}
      class={[
        "w-8 h-8 rounded font-bold text-sm flex items-center justify-center transition-all border-2",
        if(@selected,
          do: "#{@bg_class} #{@text_class} border-amber-400 ring-2 ring-amber-400/50",
          else: "bg-slate-700 text-slate-400 border-slate-600 hover:border-slate-500"
        )
      ]}
    >
      {@label}
    </button>
    """
  end
end
