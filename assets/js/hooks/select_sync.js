/**
 * SelectSync Hook
 *
 * Syncs a select element's value with a data attribute on LiveView updates.
 * This is needed because browsers ignore `selected` attribute changes after
 * initial render - they maintain internal state that doesn't respond to DOM patches.
 *
 * Usage:
 *   <select phx-hook="SelectSync" data-value={@current_value}>
 */
const SelectSync = {
  mounted() {
    this.syncValue()
  },

  updated() {
    this.syncValue()
  },

  syncValue() {
    const expectedValue = this.el.dataset.value || ""
    if (this.el.value !== expectedValue) {
      this.el.value = expectedValue
    }
  }
}

export default SelectSync
