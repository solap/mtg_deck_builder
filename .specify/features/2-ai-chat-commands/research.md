# Research: AI Chat Commands

**Feature:** 2-ai-chat-commands
**Date:** 2026-01-04

## Research Summary

This document captures technical decisions and research findings for implementing AI-powered chat commands in the MTG Deck Builder.

---

## 1. AI Provider Integration

### Decision: Anthropic Claude API (Primary)

**Rationale:**
- Clarification confirmed Claude as primary provider
- Excellent natural language understanding for command parsing
- Structured output support via tool_use for reliable JSON responses
- Aligns with "Claude Code for Magic" vision
- Cost-effective for short command parsing (minimal tokens per request)

**Alternatives Considered:**
- OpenAI GPT-4: Similar capabilities, but Claude selected per clarification
- xAI Grok: Keys available, could be future fallback option
- Local LLM (Ollama): Would eliminate API costs but adds deployment complexity

**Implementation Notes:**
- Use Anthropic Elixir SDK or raw HTTP via Tesla
- Model: claude-3-haiku for fast, cheap command parsing (~$0.25/1M input tokens)
- Use tool_use/function calling for structured command extraction
- Timeout: 10 seconds max per request

---

## 2. Command Parsing Architecture

### Decision: LLM with Structured Output (Tool Use)

**Rationale:**
- Natural language flexibility handles variations ("add", "put in", "include")
- Tool use ensures consistent JSON output format
- No regex maintenance burden
- Handles typos and fuzzy card names naturally

**Alternatives Considered:**
- Regex-based parsing: Brittle, poor UX for variations
- Intent classification + slot filling: More complex, similar results
- Hybrid (regex + LLM fallback): Added complexity for marginal benefit

**Implementation Notes:**
- Define tools for each command type (add_card, remove_card, move_card, etc.)
- LLM returns structured command with: action, card_name, quantity, board
- Client validates and executes locally

**Tool Schema Example:**
```json
{
  "name": "deck_command",
  "description": "Parse a deck building command",
  "input_schema": {
    "type": "object",
    "properties": {
      "action": {"enum": ["add", "remove", "set", "move", "query", "undo", "help"]},
      "card_name": {"type": "string"},
      "quantity": {"type": "integer", "minimum": 1, "maximum": 15},
      "source_board": {"enum": ["mainboard", "sideboard", null]},
      "target_board": {"enum": ["mainboard", "sideboard", null]},
      "query_type": {"enum": ["count", "list", "status", null]}
    },
    "required": ["action"]
  }
}
```

---

## 3. Card Name Resolution

### Decision: Two-Phase Resolution (LLM Extract → DB Fuzzy Match)

**Rationale:**
- LLM extracts user's intended card name (handles "bolt" → "lightning bolt")
- Database fuzzy search (pg_trgm) finds actual card with typo tolerance
- Keeps AI costs low (one API call per command)
- Leverages existing Cards.search/2 from MVP

**Alternatives Considered:**
- Send card database to LLM: Context too large (~27k cards)
- Embedding-based search: Overkill for name matching
- Pure LLM resolution: Hallucination risk for obscure cards

**Implementation Notes:**
- Use PostgreSQL pg_trgm extension for similarity matching
- Threshold: 0.3 similarity for suggestions, 0.8 for auto-match
- Cache recent card selections per session (GenServer or ETS)

---

## 4. API Cost Tracking

### Decision: PostgreSQL Table with Per-Request Logging

**Rationale:**
- Simple, boring technology (PostgreSQL already in stack)
- Enables historical analysis and admin dashboard
- No additional infrastructure needed
- Supports multiple providers as requested

**Alternatives Considered:**
- External service (Datadog, etc.): Adds dependency, cost
- In-memory only: Loses data on restart
- File-based logging: Harder to query

**Implementation Notes:**
- New table: `api_usage_logs`
- Fields: provider, model, input_tokens, output_tokens, estimated_cost, timestamp
- Admin LiveView at /admin/costs with date filtering
- No rate limits per clarification

---

## 5. Undo Implementation

### Decision: Single-Level Undo with Command Stack (GenServer)

**Rationale:**
- Spec requires single-level only (no redo)
- GenServer per session maintains undo state
- Stores previous deck state, not inverse operations
- Simple to implement and reason about

**Alternatives Considered:**
- Command pattern with inverse operations: More complex
- Multi-level undo: Out of scope per spec
- localStorage-based undo: Race conditions with LiveView

**Implementation Notes:**
- Store `{previous_deck_state, action_description}` tuple
- Clear after successful undo
- Only track chat-initiated actions (assign flag)

---

## 6. Chat History Persistence

### Decision: localStorage via JS Hook (Existing Pattern)

**Rationale:**
- Reuses MVP deck_storage.js pattern
- Chat history is small (~50KB max typical session)
- No server-side storage needed yet
- Persists across refreshes per spec requirement

**Alternatives Considered:**
- PostgreSQL: Requires auth system (out of scope)
- Session storage: Lost on tab close
- IndexedDB: Overkill for this use case

**Implementation Notes:**
- Extend existing DeckStorage hook
- Store last N messages (suggest 100 max)
- Include timestamps for display

---

## 7. Error Handling & Fallback

### Decision: Graceful Degradation to UI

**Rationale:**
- Per clarification: "Show error, suggest UI controls"
- No local fallback parsing
- Users can always use click-based UI

**Implementation Notes:**
- Catch API errors (timeout, rate limit, network)
- Display friendly message: "AI temporarily unavailable, please use UI controls"
- Log errors to API usage table with error flag
- No retry logic for user commands (fast fail)

---

## 8. Elixir AI Client Library

### Decision: anthropic_ex or Raw Tesla

**Rationale:**
- anthropic_ex provides typed Elixir interface
- If not stable/available, Tesla with Jason works fine
- Phoenix already uses Tesla (via Finch)

**Alternatives Considered:**
- Req: Newer HTTP client, but Tesla already in project
- HTTPoison: Older, Tesla preferred

**Implementation Notes:**
- Check hex.pm for anthropic_ex stability
- Fallback: Tesla client with custom wrapper module
- Store API key in runtime config from environment

---

## 9. Performance Targets

### Decision: Accept LLM Latency (~500ms-2s typical)

**Rationale:**
- Spec says 200ms parsing, but LLM calls are 500ms-2s realistically
- Show loading indicator during API call
- Card matching after LLM is fast (<50ms with index)

**Revised Targets:**
- Command submission to response: <2 seconds typical
- Card name resolution: <100ms (local DB)
- UI update after execution: <100ms

**Implementation Notes:**
- Show "thinking" indicator immediately on Enter
- Stream response if Claude supports it (optional optimization)
- Consider caching common command patterns (future)

---

## Open Questions (Resolved)

| Question | Resolution |
|----------|------------|
| Primary AI provider | Anthropic Claude (clarification) |
| API cost limits | None; admin dashboard instead (clarification) |
| Fallback on API failure | Show error, suggest UI (clarification) |

---

## References

- [Anthropic API Docs](https://docs.anthropic.com/)
- [Phoenix LiveView Hooks](https://hexdocs.pm/phoenix_live_view/js-interop.html)
- [PostgreSQL pg_trgm](https://www.postgresql.org/docs/current/pgtrgm.html)
