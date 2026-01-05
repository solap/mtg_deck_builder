defmodule MtgDeckBuilderWeb.Components.MobileTabs do
  @moduledoc """
  Mobile tab bar component for navigation between app sections.

  Shows a fixed bottom navigation bar on mobile (< lg breakpoint) with tabs for:
  - Deck (default)
  - Search
  - Chat
  - Brew (only when brew mode is active)

  Hidden on desktop (lg+) where the side-by-side layout is used instead.
  """

  use Phoenix.Component

  attr :active_tab, :atom, required: true
  attr :brew_mode, :boolean, default: false

  def mobile_tab_bar(assigns) do
    ~H"""
    <nav class="fixed bottom-0 left-0 right-0 bg-slate-800 border-t border-slate-700 lg:hidden z-50 safe-area-bottom">
      <div class="flex justify-around items-center h-14">
        <.tab_button tab={:deck} active={@active_tab} icon="deck" label="Deck" />
        <.tab_button tab={:search} active={@active_tab} icon="search" label="Search" />
        <.tab_button tab={:chat} active={@active_tab} icon="chat" label="Chat" />
        <%= if @brew_mode do %>
          <.tab_button tab={:brew} active={@active_tab} icon="brew" label="Brew" />
        <% end %>
      </div>
    </nav>
    """
  end

  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp tab_button(assigns) do
    is_active = assigns.active == assigns.tab
    assigns = assign(assigns, :is_active, is_active)

    ~H"""
    <button
      type="button"
      phx-click="switch_mobile_tab"
      phx-value-tab={@tab}
      class={[
        "flex flex-col items-center justify-center px-4 py-2 min-w-[60px] min-h-[44px] transition-colors",
        if(@is_active, do: "text-amber-400", else: "text-slate-400 active:text-slate-300")
      ]}
    >
      <.tab_icon icon={@icon} />
      <span class="text-xs mt-0.5">{@label}</span>
    </button>
    """
  end

  defp tab_icon(%{icon: "deck"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
      <path d="M7 3a1 1 0 000 2h6a1 1 0 100-2H7zM4 7a1 1 0 011-1h10a1 1 0 110 2H5a1 1 0 01-1-1zM2 11a2 2 0 012-2h12a2 2 0 012 2v4a2 2 0 01-2 2H4a2 2 0 01-2-2v-4z" />
    </svg>
    """
  end

  defp tab_icon(%{icon: "search"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
      <path fill-rule="evenodd" d="M8 4a4 4 0 100 8 4 4 0 000-8zM2 8a6 6 0 1110.89 3.476l4.817 4.817a1 1 0 01-1.414 1.414l-4.816-4.816A6 6 0 012 8z" clip-rule="evenodd" />
    </svg>
    """
  end

  defp tab_icon(%{icon: "chat"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
      <path fill-rule="evenodd" d="M18 10c0 3.866-3.582 7-8 7a8.841 8.841 0 01-4.083-.98L2 17l1.338-3.123C2.493 12.767 2 11.434 2 10c0-3.866 3.582-7 8-7s8 3.134 8 7zM7 9H5v2h2V9zm8 0h-2v2h2V9zM9 9h2v2H9V9z" clip-rule="evenodd" />
    </svg>
    """
  end

  defp tab_icon(%{icon: "brew"} = assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
      <path fill-rule="evenodd" d="M7 2a1 1 0 00-.707 1.707L7 4.414v3.758a1 1 0 01-.293.707l-4 4C.817 14.769 2.156 18 4.828 18h10.343c2.673 0 4.012-3.231 2.122-5.121l-4-4A1 1 0 0113 8.172V4.414l.707-.707A1 1 0 0013 2H7zm2 6.172V4h2v4.172a3 3 0 00.879 2.12l1.027 1.028a4 4 0 00-2.171.102l-.47.156a4 4 0 01-2.53 0l-.563-.187a1.993 1.993 0 00-.114-.035l1.063-1.063A3 3 0 009 8.172z" clip-rule="evenodd" />
    </svg>
    """
  end
end
