# Data Model: Brew Mode

**Feature:** 3-brew-mode
**Date:** 2026-01-04

## Overview

Brew Mode adds strategic context to decks. The core entity is the Brew, which is embedded in the existing Deck state. Additional structs support multi-agent AI orchestration.

---

## New Entities

### 1. Brew

The strategic context for a deck - archetype, key cards, combos, and theme.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| archetype | enum | nullable | `control` \| `aggro` \| `midrange` \| `combo` \| `tempo` \| `ramp` |
| key_cards | list(string) | max 10 items | Card names the deck is built around |
| combos | list(Combo) | max 5 combos | Multi-card interactions |
| theme | string | max 500 chars, nullable | Free-text deck identity description |

**Lifecycle:**
- Created when user enters Brew Mode
- Persisted with deck state in localStorage
- All fields are optional - user fills what matters to them
- Updated whenever user modifies brew sections

**Notes:**
- Not an Ecto schema - stored in localStorage as part of deck
- Elixir struct for server-side validation and manipulation
- Card names validated against database on save

---

### 2. Combo

A multi-card interaction within a brew.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| cards | list(string) | 2-4 items, required | Card names in the combo |
| description | string | max 200 chars, nullable | What the combo does |

**Lifecycle:**
- Created when user adds a combo to brew
- Validated: 2-4 cards, all must exist in database
- Displayed with completion status (all cards in deck vs missing pieces)

**Notes:**
- Embedded in Brew, not a separate entity
- Description is optional but helpful for AI context

---

### 3. BrewContext

Rich context object passed to AI for expert synthesis.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| brew | Brew | nullable | The deck's brew (can be empty) |
| deck_summary | DeckSummary | required | Aggregated deck statistics |
| question | string | required | User's question/request |
| format | atom | required | Deck format for legality context |

**Lifecycle:**
- Built on each AI chat request in Brew Mode
- Transient - not persisted
- Serialized to JSON for AI prompt context

**Notes:**
- Combines all context needed for expert analysis
- Token-efficient representation of deck state

---

### 4. DeckSummary

Aggregated deck statistics for AI context.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| format | atom | required | Selected format |
| mainboard_count | integer | 0-100 | Cards in mainboard |
| sideboard_count | integer | 0-15 | Cards in sideboard |
| cards_by_type | map | string -> integer | Count by card type |
| mana_curve | list(integer) | 8 elements, CMC 0-7+ | Cards at each CMC |
| color_distribution | map | atom -> integer | Color pip counts |
| avg_mana_value | float | 0.0-16.0 | Average CMC |
| land_count | integer | >= 0 | Total lands |
| missing_key_cards | list(string) | from brew | Key cards not in deck |
| incomplete_combos | list(Combo) | from brew | Combos missing pieces |
| legality_issues | list(string) | format violations | Cards not legal in format |

**Lifecycle:**
- Calculated on demand from current deck state
- Transient - not persisted
- Recalculated when context needed

**Notes:**
- Provides AI with deck health at a glance
- Enables "what's missing?" analysis

---

### 5. ExpertResponse (Internal)

Represents the AI's synthesized response (used for structured logging/analysis).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| content | string | required | The synthesized response text |
| experts_consulted | list(atom) | tracking only | Which expert perspectives were included |
| confidence | float | 0.0-1.0 | AI's confidence in advice |
| suggestions | list(CardSuggestion) | max 10 | Specific card recommendations |
| warnings | list(string) | any | Concerns or trade-offs mentioned |

**Lifecycle:**
- Created from AI response parsing
- Logged for analysis (optional)
- Displayed to user as chat response

**Notes:**
- Not all responses will have structured suggestions
- Used to potentially extract actionable items from response

---

### 6. CardSuggestion

A specific card recommendation from AI.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| card_name | string | required | Suggested card |
| reason | string | max 200 chars | Why this card fits |
| action | atom | `:add` \| `:remove` \| `:consider` | Suggested action |
| priority | atom | `:high` \| `:medium` \| `:low` | Importance level |

**Lifecycle:**
- Extracted from AI response when possible
- Used for "quick add" buttons in UI (optional enhancement)
- Transient

---

### 7. AgentConfig (Database Entity)

Configuration for each AI agent, including model selection and editable system prompts.

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | UUID | PK, auto-generated | Unique config identifier |
| agent_id | string | unique, required | Identifier: `orchestrator`, `command_parser`, `mana_expert`, etc. |
| name | string | max 100 chars | Human-readable name |
| description | text | nullable | What this agent does |
| provider | enum | required | `anthropic` \| `openai` \| `xai` \| `ollama` |
| model | string | required | Model identifier (e.g., "claude-sonnet-4-20250514") |
| system_prompt | text | required | Current system prompt (editable) |
| default_prompt | text | required | Original system prompt (for reset) |
| max_tokens | integer | default 1024 | Max response tokens |
| context_window | integer | default 200000 | Model's context limit |
| temperature | decimal | 0.0-2.0, default 0.7 | Response randomness |
| enabled | boolean | default true | Whether agent is active |
| cost_per_1k_input | decimal | nullable | Cost in USD per 1K input tokens |
| cost_per_1k_output | decimal | nullable | Cost in USD per 1K output tokens |
| inserted_at | datetime | auto | Record creation timestamp |
| updated_at | datetime | auto | Last modification timestamp |

**Lifecycle:**
- Seeded on first app start with default configurations
- Updated via admin UI or API
- Cached in ETS for fast access
- Never deleted (soft disable via `enabled: false`)

**Indexes:**
- `agent_id` - unique, for lookup by identifier

**Notes:**
- Stored in PostgreSQL for persistence across restarts
- System prompt editable via UI for rapid iteration
- Default prompt preserved for reset functionality
- Cost fields enable estimated cost display in UI

---

### 8. ProviderConfig (Database Entity)

Configuration for AI providers (API keys, endpoints).

| Field | Type | Constraints | Description |
|-------|------|-------------|-------------|
| id | UUID | PK, auto-generated | Unique config identifier |
| provider | enum | unique, required | `anthropic` \| `openai` \| `xai` \| `ollama` |
| api_key_env | string | required | Environment variable name for API key |
| base_url | string | nullable | Custom base URL (for self-hosted) |
| enabled | boolean | default true | Whether provider is available |
| inserted_at | datetime | auto | Record creation timestamp |
| updated_at | datetime | auto | Last modification timestamp |

**Lifecycle:**
- Seeded with defaults (anthropic, openai, xai)
- API keys loaded from environment variables at runtime
- Base URL allows custom endpoints (Ollama, proxies)

**Notes:**
- API keys never stored in database, only env var names
- Enables runtime provider switching without code changes

---

## Entity Relationships

```
┌─────────────────────────────────────────────────────────────┐
│                    Deck State (localStorage)                 │
├─────────────────────────────────────────────────────────────┤
│  format: "modern"                                           │
│  mainboard: [...]                                           │
│  sideboard: [...]                                           │
│  removed: [...]                                             │
│  brew_mode: true                                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                      Brew                               │ │
│  │  archetype: "control"                                   │ │
│  │  key_cards: ["Teferi", "Verdict"]                       │ │
│  │  combos: [...]                                          │ │
│  │  theme: "Planeswalker control..."                       │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ builds context
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                    BrewContext (transient)                   │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ uses config from
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 AgentConfig (PostgreSQL)                     │
├─────────────────────────────────────────────────────────────┤
│  agent_id: "orchestrator"                                   │
│  provider: "anthropic"                                      │
│  model: "claude-sonnet-4-20250514"                          │
│  system_prompt: "You are a MTG advisor..."                  │
│  temperature: 0.7                                           │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ formatted by
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 ProviderAdapter                              │
│  (Anthropic, OpenAI, etc.)                                  │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ sends to
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 AI Provider API                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Database Migrations

### AgentConfig Migration

```elixir
# priv/repo/migrations/TIMESTAMP_create_agent_configs.exs

def change do
  create table(:agent_configs, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :agent_id, :string, null: false
    add :name, :string, null: false
    add :description, :text
    add :provider, :string, null: false
    add :model, :string, null: false
    add :system_prompt, :text, null: false
    add :default_prompt, :text, null: false
    add :max_tokens, :integer, default: 1024
    add :context_window, :integer, default: 200_000
    add :temperature, :decimal, precision: 3, scale: 2, default: 0.7
    add :enabled, :boolean, default: true
    add :cost_per_1k_input, :decimal, precision: 10, scale: 6
    add :cost_per_1k_output, :decimal, precision: 10, scale: 6

    timestamps()
  end

  create unique_index(:agent_configs, [:agent_id])
end
```

### ProviderConfig Migration

```elixir
# priv/repo/migrations/TIMESTAMP_create_provider_configs.exs

def change do
  create table(:provider_configs, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :provider, :string, null: false
    add :api_key_env, :string, null: false
    add :base_url, :string
    add :enabled, :boolean, default: true

    timestamps()
  end

  create unique_index(:provider_configs, [:provider])
end
```

---

## Original Entity Relationships (Reference)

```
┌─────────────────────────────────────────────────────────────┐
│                    Deck State (localStorage)                 │
├─────────────────────────────────────────────────────────────┤
│  format: "modern"                                           │
│  mainboard: [...]                                           │
│  sideboard: [...]                                           │
│  removed: [...]                                             │
│  brew_mode: true                                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                      Brew                               │ │
│  │  archetype: "control"                                   │ │
│  │  key_cards: ["Teferi", "Verdict"]                       │ │
│  │  combos: [                                              │ │
│  │    ┌────────────────────────────────────────┐           │ │
│  │    │ Combo                                  │           │ │
│  │    │ cards: ["Card A", "Card B"]            │           │ │
│  │    │ description: "Infinite combo"         │           │ │
│  │    └────────────────────────────────────────┘           │ │
│  │  ]                                                      │ │
│  │  theme: "Planeswalker control..."                       │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ builds context
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                    BrewContext (transient)                   │
├─────────────────────────────────────────────────────────────┤
│  brew: %Brew{...}                                           │
│  deck_summary: %DeckSummary{...}                            │
│  question: "What should I add?"                             │
│  format: :modern                                            │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ sent to AI
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 Orchestrator (Claude Sonnet)                 │
│                                                             │
│  System prompt contains expert personas:                     │
│  - Mana Base Expert                                         │
│  - Synergy & Interactions Expert                            │
│  - Card Evaluation Expert                                   │
│  - Meta & Matchups Expert                                   │
│  - [Situational experts as relevant]                        │
└─────────────────────────────────────────────────────────────┘
                    │
                    │ synthesized response
                    ▼
┌─────────────────────────────────────────────────────────────┐
│                 ExpertResponse (parsed)                      │
├─────────────────────────────────────────────────────────────┤
│  content: "For your control deck..."                        │
│  suggestions: [%CardSuggestion{...}]                        │
│  warnings: ["Consider sideboard for aggro matchup"]         │
└─────────────────────────────────────────────────────────────┘
```

---

## Existing Entities (Extended)

### Deck State (localStorage)

Extended with brew-related fields:

| New Field | Type | Description |
|-----------|------|-------------|
| brew_mode | boolean | Whether user is in Brew Mode layout |
| brew | Brew \| null | The deck's strategic context |

---

## Existing Entities (Unchanged)

These entities from MVP are used but not modified:

| Entity | Usage in This Feature |
|--------|----------------------|
| Card | Referenced by name in key_cards and combos |
| DeckCard | Checked for key card presence, combo completion |
| ApiUsageLog | Extended to log Sonnet orchestration calls |

---

## Validation Rules

### Brew
- `archetype` must be valid enum or null
- `key_cards` max 10 items, each must exist in cards table
- `combos` max 5 items, each validated as Combo
- `theme` max 500 characters

### Combo
- `cards` must have 2-4 items
- Each card name must exist in cards table
- `description` max 200 characters

### BrewContext
- `deck_summary` always calculated fresh from deck state
- `question` must be non-empty
- `format` must be valid format enum

---

## State Transitions

### Entering Brew Mode
```
1. User clicks "Brew Mode" toggle
2. System sets brew_mode: true
3. System initializes empty brew if none exists: { archetype: null, key_cards: [], combos: [], theme: null }
4. Layout switches to show brew panel
5. State persisted to localStorage
```

### Editing Brew
```
1. User modifies brew section (archetype, key cards, combos, theme)
2. Client-side validation (card name autocomplete from DB)
3. Server-side validation on blur/submit
4. Valid: Update brew in deck state, persist
5. Invalid: Show error, revert to previous value
```

### Asking AI Question
```
1. User submits question in chat
2. System builds BrewContext from current deck + brew
3. System sends to Orchestrator (Sonnet)
4. Response parsed into ExpertResponse
5. Content displayed in chat
6. Suggestions available for quick action (optional)
```

### Exiting Brew Mode
```
1. User clicks "Brew Mode" toggle (off)
2. System sets brew_mode: false
3. Layout switches to normal view
4. Brew data preserved (not deleted)
5. State persisted to localStorage
```

---

## JSON Schema (localStorage)

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "format": { "type": "string" },
    "mainboard": { "type": "array" },
    "sideboard": { "type": "array" },
    "removed": { "type": "array" },
    "brew_mode": { "type": "boolean", "default": false },
    "brew": {
      "type": "object",
      "properties": {
        "archetype": {
          "type": ["string", "null"],
          "enum": ["control", "aggro", "midrange", "combo", "tempo", "ramp", null]
        },
        "key_cards": {
          "type": "array",
          "items": { "type": "string" },
          "maxItems": 10
        },
        "combos": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "cards": {
                "type": "array",
                "items": { "type": "string" },
                "minItems": 2,
                "maxItems": 4
              },
              "description": { "type": ["string", "null"], "maxLength": 200 }
            },
            "required": ["cards"]
          },
          "maxItems": 5
        },
        "theme": { "type": ["string", "null"], "maxLength": 500 }
      }
    }
  }
}
```
