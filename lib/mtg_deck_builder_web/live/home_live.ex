defmodule MtgDeckBuilderWeb.HomeLive do
  use MtgDeckBuilderWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-12 text-center">
      <h2 class="text-3xl font-bold text-amber-400 mb-4">Welcome to MTG Deck Builder</h2>
      <p class="text-lg text-slate-300 mb-8">
        Build, manage, and validate your Magic: The Gathering decks with real-time statistics.
      </p>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-12">
        <div class="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h3 class="text-xl font-semibold text-amber-400 mb-2">Search Cards</h3>
          <p class="text-slate-400">
            Search from over 27,000 cards with instant results from our local database.
          </p>
        </div>

        <div class="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h3 class="text-xl font-semibold text-amber-400 mb-2">Build Decks</h3>
          <p class="text-slate-400">
            Add cards to mainboard and sideboard with automatic format validation.
          </p>
        </div>

        <div class="bg-slate-800 rounded-lg p-6 border border-slate-700">
          <h3 class="text-xl font-semibold text-amber-400 mb-2">Track Stats</h3>
          <p class="text-slate-400">
            View mana curve, color distribution, and deck composition in real-time.
          </p>
        </div>
      </div>

      <div class="bg-slate-800 rounded-lg p-6 border border-slate-700 max-w-md mx-auto">
        <h3 class="text-lg font-semibold text-amber-400 mb-3">Supported Formats</h3>
        <div class="flex flex-wrap justify-center gap-2">
          <span class="bg-slate-700 px-3 py-1 rounded-full text-sm">Standard</span>
          <span class="bg-slate-700 px-3 py-1 rounded-full text-sm">Modern</span>
          <span class="bg-slate-700 px-3 py-1 rounded-full text-sm">Pioneer</span>
          <span class="bg-slate-700 px-3 py-1 rounded-full text-sm">Legacy</span>
          <span class="bg-slate-700 px-3 py-1 rounded-full text-sm">Vintage</span>
          <span class="bg-slate-700 px-3 py-1 rounded-full text-sm">Pauper</span>
        </div>
      </div>

      <p class="mt-8 text-slate-500 text-sm">
        Run <code class="bg-slate-800 px-2 py-1 rounded">mix cards.import</code> to load card data before starting.
      </p>
    </div>
    """
  end
end
