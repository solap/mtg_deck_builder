const CHAT_HISTORY_KEY = "mtg_deck_builder_chat_history";
const MAX_HISTORY = 50;

const ChatInput = {
  mounted() {
    this.commandHistory = [];
    this.historyIndex = -1;
    this.tempInput = "";

    // Load chat history from localStorage
    const savedHistory = localStorage.getItem(CHAT_HISTORY_KEY);
    if (savedHistory) {
      try {
        const messages = JSON.parse(savedHistory);
        this.pushEvent("load_chat", { messages });
      } catch (e) {
        console.error("Failed to parse chat history:", e);
        localStorage.removeItem(CHAT_HISTORY_KEY);
      }
    }

    // Get input element
    this.inputEl = this.el.querySelector("input[name='command']");

    if (this.inputEl) {
      // Handle keyboard navigation
      this.inputEl.addEventListener("keydown", (e) => {
        switch (e.key) {
          case "ArrowUp":
            e.preventDefault();
            this.navigateHistory(-1);
            break;
          case "ArrowDown":
            e.preventDefault();
            this.navigateHistory(1);
            break;
          case "Escape":
            e.preventDefault();
            this.clearInput();
            break;
        }
      });
    }

    // Listen for sync events from server
    this.handleEvent("sync_chat", ({ messages }) => {
      // Save chat messages to localStorage
      const trimmed = messages.slice(-MAX_HISTORY);
      localStorage.setItem(CHAT_HISTORY_KEY, JSON.stringify(trimmed));

      // Update command history for arrow key navigation
      this.commandHistory = trimmed
        .filter((m) => m.role === "user")
        .map((m) => m.content);
    });

    // Listen for focus event (when "/" is pressed)
    this.handleEvent("focus_chat", () => {
      if (this.inputEl) {
        this.inputEl.focus();
      }
    });

    // Listen for command sent to add to history
    this.handleEvent("command_sent", ({ command }) => {
      if (command && command.trim()) {
        this.commandHistory.push(command);
        this.historyIndex = -1;
        this.tempInput = "";
      }
    });
  },

  navigateHistory(direction) {
    if (!this.inputEl || this.commandHistory.length === 0) return;

    // Save current input if starting to navigate
    if (this.historyIndex === -1 && direction === -1) {
      this.tempInput = this.inputEl.value;
    }

    const newIndex = this.historyIndex + direction * -1;

    if (newIndex < 0) {
      // Back to temp input
      this.historyIndex = -1;
      this.inputEl.value = this.tempInput;
    } else if (newIndex < this.commandHistory.length) {
      this.historyIndex = newIndex;
      const historyValue = this.commandHistory[this.commandHistory.length - 1 - newIndex];
      this.inputEl.value = historyValue;
    }
    // Else stay at oldest history item

    // Move cursor to end
    this.inputEl.setSelectionRange(this.inputEl.value.length, this.inputEl.value.length);
  },

  clearInput() {
    if (this.inputEl) {
      this.inputEl.value = "";
      this.historyIndex = -1;
      this.tempInput = "";
    }
  },

  destroyed() {
    // Clean up
  }
};

export default ChatInput;
