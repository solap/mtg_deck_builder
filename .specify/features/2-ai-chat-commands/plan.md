# Implementation Plan: AI Chat Commands

**Feature:** 2-ai-chat-commands
**Version:** 1.0.0
**Date:** 2026-01-04
**Branch:** `2-ai-chat-commands`

## Technical Context

| Aspect | Decision | Reference |
|--------|----------|-----------|
| Backend | Elixir + Phoenix | Constitution: Boring Technology |
| Frontend | Phoenix LiveView | Existing MVP pattern |
| Database | PostgreSQL | Constitution: Boring Technology |
| AI Provider | Anthropic Claude (Haiku) | Clarification: Primary provider |
| AI Client | Tesla + custom wrapper | research.md |
| Command Parsing | LLM tool_use | research.md |
| Card Matching | pg_trgm fuzzy search | research.md |
| Chat Storage | localStorage | spec.md |
| Cost Storage | PostgreSQL | data-model.md |

## Constitution Compliance

| Principle | Status | Implementation |
|-----------|--------|----------------|
| Incremental Delivery | ✅ | 5 testable increments below |
| AI-Native Architecture | ✅ | Anthropic API with tool_use, multi-provider logging |
| Boring Technology | ✅ | Standard Phoenix/LiveView, PostgreSQL, Tesla |
| Working Code Over Perfect | ✅ | Simple undo, localStorage, no auth on admin |

## Architecture Overview

```
User Input (chat command)
         │
         ▼
┌─────────────────────────┐
│    Chat LiveView        │
│  (deck_live.ex update)  │
└──────────┬──────────────┘
           │ "submit_command" event
           ▼
┌─────────────────────────┐
│   Command Parser        │
│  (Anthropic Claude API) │──────► ApiUsageLog (PostgreSQL)
└──────────┬──────────────┘
           │ ParsedCommand struct
           ▼
┌─────────────────────────┐
│   Card Resolver         │
│  (pg_trgm fuzzy match)  │
└──────────┬──────────────┘
           │ Card entity
           ▼
┌─────────────────────────┐
│  Command Executor       │
│  (deck modifications)   │──────► UndoState (GenServer)
└──────────┬──────────────┘
           │ Updated Deck
           ▼
┌─────────────────────────┐
│   Response Formatter    │
│  (user-friendly msgs)   │
└──────────┬──────────────┘
           │ "command_result" event
           ▼
┌─────────────────────────┐
│  Chat UI + localStorage │
└─────────────────────────┘
```

## Implementation Increments

Each increment is independently testable before proceeding.

### Increment 1: Anthropic API Integration
**Test:** Parse "add 4 lightning bolt" via API, get structured response

**Tasks:**
1. Add Tesla configuration for Anthropic API in `config/runtime.exs`
2. Create `lib/mtg_deck_builder/ai/anthropic_client.ex` module
3. Implement `AnthropicClient.parse_command/1` with tool_use schema
4. Create `lib/mtg_deck_builder/ai/parsed_command.ex` struct
5. Create migration for `api_usage_logs` table
6. Create `lib/mtg_deck_builder/ai/api_usage_log.ex` Ecto schema
7. Create `lib/mtg_deck_builder/ai/api_logger.ex` for logging calls
8. Write tests with mocked API responses

**Artifacts:**
- `lib/mtg_deck_builder/ai/anthropic_client.ex`
- `lib/mtg_deck_builder/ai/parsed_command.ex`
- `lib/mtg_deck_builder/ai/api_usage_log.ex`
- `lib/mtg_deck_builder/ai/api_logger.ex`
- `priv/repo/migrations/*_create_api_usage_logs.exs`
- `test/mtg_deck_builder/ai/` tests

**Acceptance:**
```elixir
iex> AnthropicClient.parse_command("add 4 lightning bolt")
{:ok, %ParsedCommand{action: :add, card_name: "lightning bolt", quantity: 4, target_board: :mainboard}}

iex> Repo.aggregate(ApiUsageLog, :count)
1
```

---

### Increment 2: Card Resolution & Fuzzy Matching
**Test:** Resolve "litning bolt" to "Lightning Bolt" with suggestions

**Tasks:**
1. Add pg_trgm extension migration (if not already present)
2. Create `lib/mtg_deck_builder/chat/card_resolver.ex` module
3. Implement `CardResolver.resolve/2` with fuzzy matching
4. Implement `CardResolver.suggest/2` for near-matches
5. Create ETS table for recent card selections
6. Implement `CardResolver.remember_selection/2` and `get_recent/1`
7. Write tests for fuzzy matching and disambiguation

**Artifacts:**
- `lib/mtg_deck_builder/chat/card_resolver.ex`
- `priv/repo/migrations/*_add_pg_trgm.exs` (if needed)
- `test/mtg_deck_builder/chat/card_resolver_test.exs`

**Acceptance:**
```elixir
iex> CardResolver.resolve("litning bolt", :modern)
{:ambiguous, [%Card{name: "Lightning Bolt"}, ...]}

iex> CardResolver.resolve("lightning bolt", :modern)
{:ok, %Card{name: "Lightning Bolt"}}
```

---

### Increment 3: Command Execution & Undo
**Test:** Execute add command, undo restores previous state

**Tasks:**
1. Create `lib/mtg_deck_builder/chat/command_executor.ex` module
2. Implement execute functions for each command type (add, remove, set, move, query)
3. Create `lib/mtg_deck_builder/chat/undo_server.ex` GenServer
4. Implement single-level undo with deck state storage
5. Integrate with existing `Decks` context for validation
6. Create `lib/mtg_deck_builder/chat/response_formatter.ex` for messages
7. Write tests for all command types and undo

**Artifacts:**
- `lib/mtg_deck_builder/chat/command_executor.ex`
- `lib/mtg_deck_builder/chat/undo_server.ex`
- `lib/mtg_deck_builder/chat/response_formatter.ex`
- `test/mtg_deck_builder/chat/` tests

**Acceptance:**
```elixir
iex> deck = %Deck{mainboard: []}
iex> {:ok, new_deck, msg} = CommandExecutor.execute(%ParsedCommand{action: :add, ...}, deck)
iex> msg
"Added 4x Lightning Bolt to mainboard"

iex> {:ok, restored_deck, undo_msg} = UndoServer.undo()
iex> undo_msg
"Undone: Added 4x Lightning Bolt to mainboard"
```

---

### Increment 4: Chat UI & LiveView Integration
**Test:** Type command in chat, see response, deck updates in real-time

**Tasks:**
1. Update `deck_live.ex` with chat-related assigns (messages, input, processing)
2. Create chat input component in `deck_live.html.heex`
3. Create chat message list component
4. Implement `handle_event("submit_command", ...)` handler
5. Implement command history (up/down arrows) via JS hook
6. Create `assets/js/hooks/chat_input.js` for keyboard handling
7. Extend `deck_storage.js` to persist chat history
8. Add loading indicator during AI processing
9. Implement disambiguation UI (numbered list selection)
10. Add `/` keyboard shortcut to focus chat

**Artifacts:**
- Updates to `lib/mtg_deck_builder_web/live/deck_live.ex`
- Updates to `lib/mtg_deck_builder_web/live/deck_live.html.heex`
- `lib/mtg_deck_builder_web/components/chat_component.ex`
- `assets/js/hooks/chat_input.js`
- Updates to `assets/js/hooks/deck_storage.js`

**Acceptance:**
- Type "add 4 lightning bolt" → see confirmation message
- Press `/` → chat input focuses
- Press `↑` → previous command appears
- Refresh page → chat history restored

---

### Increment 5: Admin Cost Dashboard & Polish
**Test:** View /admin/costs showing API usage breakdown

**Tasks:**
1. Create `lib/mtg_deck_builder_web/live/admin/costs_live.ex` LiveView
2. Add route `/admin/costs` to router
3. Create `lib/mtg_deck_builder/ai/cost_stats.ex` for aggregation queries
4. Implement date range filtering
5. Implement provider breakdown display
6. Add error handling for API failures (graceful degradation)
7. Add help command response
8. Final testing across all scenarios
9. Run credo and dialyzer

**Artifacts:**
- `lib/mtg_deck_builder_web/live/admin/costs_live.ex`
- `lib/mtg_deck_builder_web/live/admin/costs_live.html.heex`
- `lib/mtg_deck_builder/ai/cost_stats.ex`
- Router updates

**Acceptance:**
- Visit `/admin/costs` → see cost breakdown by provider
- Filter by date range → totals update
- API fails → chat shows error, UI still works

---

## File Structure (New/Modified)

```
lib/
├── mtg_deck_builder/
│   ├── ai/
│   │   ├── anthropic_client.ex    # NEW: Claude API client
│   │   ├── parsed_command.ex      # NEW: Command struct
│   │   ├── api_usage_log.ex       # NEW: Ecto schema
│   │   ├── api_logger.ex          # NEW: Logging service
│   │   └── cost_stats.ex          # NEW: Aggregation queries
│   └── chat/
│       ├── card_resolver.ex       # NEW: Fuzzy card matching
│       ├── command_executor.ex    # NEW: Execute commands
│       ├── undo_server.ex         # NEW: Undo GenServer
│       └── response_formatter.ex  # NEW: Message formatting
├── mtg_deck_builder_web/
│   ├── live/
│   │   ├── deck_live.ex           # MODIFIED: Add chat
│   │   └── admin/
│   │       └── costs_live.ex      # NEW: Admin dashboard
│   └── components/
│       └── chat_component.ex      # NEW: Chat UI
└── assets/
    └── js/
        └── hooks/
            ├── chat_input.js      # NEW: Keyboard handling
            └── deck_storage.js    # MODIFIED: Chat persistence
```

---

## Dependencies

```elixir
# mix.exs - Add to existing deps
defp deps do
  [
    # ... existing deps ...
    {:tesla, "~> 1.7"},           # Already present for bulk import
    {:jason, "~> 1.4"},           # Already present
    # No new dependencies needed
  ]
end
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Anthropic API outage | Chat unusable | Graceful degradation to UI with clear message |
| API rate limiting | Slow responses | Accept latency; no user rate limits per clarification |
| High API costs | Budget overrun | Admin dashboard for visibility; no limits per clarification |
| Fuzzy match false positives | Wrong card added | Disambiguation UI with confirmation |
| pg_trgm not installed | Fuzzy search fails | Migration adds extension; fall back to ILIKE |

---

## Cost Estimates

| Model | Cost | Usage Estimate |
|-------|------|----------------|
| Claude 3 Haiku | $0.25/1M input, $1.25/1M output | ~125 tokens/command |
| Per command | ~$0.00003 | Negligible per user |
| 1000 commands/day | ~$0.03/day | ~$1/month |

---

## Next Steps After Plan

1. `/speckit.tasks` - Generate detailed task list from this plan
2. `/speckit.taskstoissues` - Create GitHub issues from tasks
3. Begin Increment 1 implementation
