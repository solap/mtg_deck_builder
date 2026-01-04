# Data Model: AI Chat Commands

**Feature:** 2-ai-chat-commands
**Date:** 2026-01-04

## Overview

This feature adds new entities for chat functionality and API cost tracking. It extends the existing MVP data model without modifying existing entities.

---

## New Entities

### 1. ChatMessage

Represents a single message in the chat conversation (user command or system response).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | UUID | PK, auto-generated | Unique message identifier |
| role | enum | `user` \| `assistant` \| `system` | Message author role |
| content | string | max 2000 chars | Message text content |
| timestamp | datetime | required | When message was created |
| command_type | enum | nullable | Parsed command type (add, remove, etc.) |
| success | boolean | nullable | Whether command executed successfully |
| error_message | string | nullable | Error details if command failed |

**Lifecycle:**
- Created on user input or system response
- Stored in localStorage (not database)
- Cleared on explicit user action or session limit (100 messages)

**Notes:**
- Not persisted to PostgreSQL (localStorage only)
- Represented as Elixir struct, not Ecto schema

---

### 2. ParsedCommand

Represents the structured output from AI command parsing.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| action | enum | required | `add` \| `remove` \| `set` \| `move` \| `query` \| `undo` \| `help` |
| card_name | string | nullable | Extracted card name from user input |
| quantity | integer | 1-15, default 1 | Number of cards affected |
| source_board | enum | nullable | `mainboard` \| `sideboard` for move/remove |
| target_board | enum | default `mainboard` | `mainboard` \| `sideboard` for add/move |
| query_type | enum | nullable | `count` \| `list` \| `status` for query commands |
| raw_input | string | required | Original user input text |
| confidence | float | 0.0-1.0 | AI confidence in parsing |

**Lifecycle:**
- Created from AI API response
- Used transiently for command execution
- Not persisted

**Notes:**
- Elixir struct with validation
- Maps directly to AI tool_use schema

---

### 3. ApiUsageLog (Database Entity)

Tracks all AI API calls for cost monitoring.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | UUID | PK, auto-generated | Unique log identifier |
| provider | enum | required | `anthropic` \| `openai` \| `xai` |
| model | string | required | Model identifier (e.g., "claude-3-haiku") |
| input_tokens | integer | >= 0 | Tokens sent to API |
| output_tokens | integer | >= 0 | Tokens received from API |
| estimated_cost_cents | integer | >= 0 | Cost in cents (USD) |
| latency_ms | integer | >= 0 | Request duration in milliseconds |
| success | boolean | required | Whether API call succeeded |
| error_type | string | nullable | Error classification if failed |
| endpoint | string | required | API endpoint called |
| inserted_at | datetime | auto | Record creation timestamp |

**Lifecycle:**
- Created after every AI API call (success or failure)
- Never updated or deleted (append-only log)
- Queried for admin dashboard

**Indexes:**
- `provider` - for filtering by provider
- `inserted_at` - for date range queries
- `(provider, inserted_at)` - composite for dashboard

---

### 4. UndoState

Holds the previous deck state for single-level undo.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| previous_deck | Deck struct | nullable | Full deck state before last action |
| action_description | string | nullable | Human-readable description |
| timestamp | datetime | nullable | When action was performed |

**Lifecycle:**
- Updated on each chat-initiated deck modification
- Cleared after successful undo
- One instance per session (GenServer state)

**Notes:**
- In-memory only (GenServer state)
- Not persisted across page refresh

---

### 5. RecentCardSelection

Caches recently selected cards for faster repeat commands.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| input_text | string | max 100 chars | What user typed |
| resolved_card_id | UUID | FK to cards | Which card was selected |
| selected_at | datetime | required | When selection was made |

**Lifecycle:**
- Created when user confirms ambiguous card selection
- Expires after 1 hour or session end
- Max 20 entries per session (LRU eviction)

**Notes:**
- ETS table or GenServer state
- Not persisted to database

---

## Entity Relationships

```
┌─────────────────┐
│   ChatMessage   │ (localStorage)
│ - role          │
│ - content       │
│ - command_type  │
└────────┬────────┘
         │ triggers parsing
         ▼
┌─────────────────┐
│  ParsedCommand  │ (transient struct)
│ - action        │
│ - card_name     │
│ - quantity      │
└────────┬────────┘
         │ references
         ▼
┌─────────────────┐      ┌─────────────────┐
│      Card       │◄─────│RecentCardSelect │ (ETS)
│   (existing)    │      │ - input_text    │
└─────────────────┘      │ - resolved_id   │
                         └─────────────────┘
         │
         │ modifies
         ▼
┌─────────────────┐      ┌─────────────────┐
│      Deck       │◄─────│   UndoState     │ (GenServer)
│   (existing)    │      │ - previous_deck │
└─────────────────┘      └─────────────────┘

┌─────────────────┐
│  ApiUsageLog    │ (PostgreSQL)
│ - provider      │
│ - tokens        │
│ - cost          │
└─────────────────┘
```

---

## Existing Entities (Unchanged)

These entities from MVP are used but not modified:

| Entity | Usage in This Feature |
|--------|----------------------|
| Card | Looked up by fuzzy name match |
| Deck | Modified by chat commands |
| DeckCard | Added/removed/moved by commands |

---

## Database Migration

New table required:

```elixir
# priv/repo/migrations/TIMESTAMP_create_api_usage_logs.exs

def change do
  create table(:api_usage_logs, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :provider, :string, null: false
    add :model, :string, null: false
    add :input_tokens, :integer, null: false, default: 0
    add :output_tokens, :integer, null: false, default: 0
    add :estimated_cost_cents, :integer, null: false, default: 0
    add :latency_ms, :integer, null: false, default: 0
    add :success, :boolean, null: false, default: true
    add :error_type, :string
    add :endpoint, :string, null: false

    timestamps(updated_at: false)
  end

  create index(:api_usage_logs, [:provider])
  create index(:api_usage_logs, [:inserted_at])
  create index(:api_usage_logs, [:provider, :inserted_at])
end
```

---

## Validation Rules

### ParsedCommand
- `action` must be valid enum value
- `quantity` must be 1-15
- `card_name` required for add/remove/set/move actions
- `target_board` required for add/move actions

### ApiUsageLog
- `provider` must be valid enum
- `input_tokens` and `output_tokens` must be non-negative
- `estimated_cost_cents` must be non-negative
- `endpoint` must be non-empty string

### ChatMessage
- `content` must be non-empty, max 2000 characters
- `role` must be valid enum
- `timestamp` must be valid datetime
