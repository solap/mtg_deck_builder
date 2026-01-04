const STORAGE_KEY = "mtg_deck_builder_deck";

const DeckStorage = {
  mounted() {
    // Load deck from localStorage on mount
    const savedDeck = localStorage.getItem(STORAGE_KEY);
    if (savedDeck) {
      try {
        JSON.parse(savedDeck); // Validate JSON
        this.pushEvent("load_deck", { deck_json: savedDeck });
      } catch (e) {
        console.error("Failed to parse saved deck:", e);
        localStorage.removeItem(STORAGE_KEY);
      }
    }

    // Listen for sync events from server
    this.handleEvent("sync_deck", ({ deck_json }) => {
      localStorage.setItem(STORAGE_KEY, deck_json);
    });

    // Listen for clear events
    this.handleEvent("clear_deck", () => {
      localStorage.removeItem(STORAGE_KEY);
    });
  },

  destroyed() {
    // Clean up if needed
  }
};

export default DeckStorage;
