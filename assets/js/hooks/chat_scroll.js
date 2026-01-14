// Auto-scroll chat messages to bottom when new messages arrive
const ChatScroll = {
  mounted() {
    this.scrollToBottom();
  },
  updated() {
    this.scrollToBottom();
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight;
  }
};

export default ChatScroll;
