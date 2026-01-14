# API Contracts: Brew Mode

**Feature:** 3-brew-mode
**Date:** 2026-01-04

## Overview

Brew Mode extends the existing LiveView event system with new events for brew management and AI orchestration. Additionally, it adds HTTP endpoints for agent configuration management.

---

## LiveView Events

### Client → Server Events

#### 1. `toggle_brew_mode`

User toggles Brew Mode on/off.

**Payload:**
```elixir
%{}  # No payload - toggles current state
```

**Response:**
- Updates `brew_mode` assign
- If entering brew mode and no brew exists, initializes empty brew
- Triggers `sync_deck` to persist state

**Example:**
```javascript
this.pushEvent("toggle_brew_mode", {})
```

---

#### 2. `update_brew_archetype`

User selects/changes deck archetype.

**Payload:**
```elixir
%{
  "archetype" => "control"  # string | null, enum value
}
```

**Valid Values:** `"control"`, `"aggro"`, `"midrange"`, `"combo"`, `"tempo"`, `"ramp"`, `null`

**Response:**
- Success: Updates brew.archetype, triggers `sync_deck`
- Error: Returns `brew_error` event (invalid value)

---

#### 3. `add_key_card`

User adds a card to key cards list.

**Payload:**
```elixir
%{
  "card_name" => "Teferi, Hero of Dominaria"  # string, card name
}
```

**Response:**
- Success: Adds to key_cards, triggers `sync_deck`
- Error: `brew_error` with reason:
  - `card_not_found`: Card doesn't exist in database
  - `duplicate`: Card already in key_cards
  - `limit_exceeded`: Already at 10 key cards

---

#### 4. `remove_key_card`

User removes a card from key cards list.

**Payload:**
```elixir
%{
  "card_name" => "Teferi, Hero of Dominaria"  # string
}
```

**Response:**
- Success: Removes from key_cards, triggers `sync_deck`
- Error: `brew_error` if card not in list

---

#### 5. `add_combo`

User adds a new combo to the brew.

**Payload:**
```elixir
%{
  "cards" => ["Splinter Twin", "Deceiver Exarch"],  # list of 2-4 strings
  "description" => "Infinite tokens"  # string | null, max 200 chars
}
```

**Response:**
- Success: Adds combo to combos list, triggers `sync_deck`
- Error: `brew_error` with reason:
  - `invalid_card_count`: Not 2-4 cards
  - `card_not_found`: One or more cards don't exist
  - `limit_exceeded`: Already at 5 combos

---

#### 6. `remove_combo`

User removes a combo from the brew.

**Payload:**
```elixir
%{
  "index" => 0  # integer, 0-based index in combos list
}
```

**Response:**
- Success: Removes combo at index, triggers `sync_deck`
- Error: `brew_error` if index out of bounds

---

#### 7. `update_combo`

User modifies an existing combo.

**Payload:**
```elixir
%{
  "index" => 0,
  "cards" => ["Card A", "Card B", "Card C"],
  "description" => "Updated description"
}
```

**Response:**
- Same validation as `add_combo`
- Updates combo at specified index

---

#### 8. `update_theme`

User updates the theme description.

**Payload:**
```elixir
%{
  "theme" => "UW Control focusing on planeswalker win conditions"  # string | null, max 500 chars
}
```

**Response:**
- Success: Updates brew.theme, triggers `sync_deck`
- Error: `brew_error` if exceeds 500 characters

---

#### 9. `submit_brew_question`

User asks AI a question in Brew Mode (uses Orchestrator).

**Payload:**
```elixir
%{
  "question" => "What cards should I add to improve my control matchup?"  # string, max 1000 chars
}
```

**Response:**
- Success: Pushes `expert_response` event to client
- Processing: Pushes `ai_processing` event (true/false)
- Error: Pushes `expert_error` event

**Notes:**
- Different from Phase 2 `submit_command` - this is conversational, not command parsing
- Uses Claude Sonnet with Orchestrator prompt
- Builds BrewContext from current deck + brew state

---

#### 10. `search_cards_for_brew`

User searches for cards to add to key cards or combos (autocomplete).

**Payload:**
```elixir
%{
  "query" => "Tef",  # partial card name
  "limit" => 5  # max results, default 5
}
```

**Response:**
- Pushes `card_suggestions` event with matching cards

---

### Server → Client Events

#### 1. `brew_updated`

Brew state has changed.

**Payload:**
```elixir
%{
  "brew" => %{
    "archetype" => "control",
    "key_cards" => ["Teferi, Hero of Dominaria"],
    "combos" => [
      %{"cards" => ["Card A", "Card B"], "description" => "Combo"}
    ],
    "theme" => "UW Control..."
  },
  "key_cards_status" => [
    %{"name" => "Teferi, Hero of Dominaria", "present" => true, "count" => 2}
  ],
  "combos_status" => [
    %{
      "index" => 0,
      "complete" => false,
      "cards" => [
        %{"name" => "Card A", "present" => true},
        %{"name" => "Card B", "present" => false}
      ]
    }
  ]
}
```

---

#### 2. `brew_error`

Brew operation failed.

**Payload:**
```elixir
%{
  "error_type" => "card_not_found",  # error code
  "message" => "Card 'Teferi Herp' not found. Did you mean 'Teferi, Hero of Dominaria'?",
  "suggestions" => ["Teferi, Hero of Dominaria", "Teferi, Time Raveler"]
}
```

---

#### 3. `expert_response`

AI Orchestrator response to user question.

**Payload:**
```elixir
%{
  "content" => "For your control deck, I'd recommend considering...",
  "suggestions" => [  # optional, may be empty
    %{
      "card_name" => "Supreme Verdict",
      "reason" => "Uncounterable board wipe for control mirror",
      "action" => "add"
    }
  ],
  "warnings" => [  # optional, may be empty
    "Your mana base is light on white sources for Verdict"
  ]
}
```

---

#### 4. `expert_error`

AI Orchestrator request failed.

**Payload:**
```elixir
%{
  "message" => "Unable to analyze right now. Please try again.",
  "fallback_stats" => %{  # provide local analysis
    "mainboard_count" => 58,
    "missing_key_cards" => ["Card X"],
    "incomplete_combos" => 1
  }
}
```

---

#### 5. `card_suggestions`

Autocomplete results for card search in brew.

**Payload:**
```elixir
%{
  "cards" => [
    %{"name" => "Teferi, Hero of Dominaria", "mana_cost" => "{3}{W}{U}"},
    %{"name" => "Teferi, Time Raveler", "mana_cost" => "{1}{W}{U}"}
  ]
}
```

---

## External API: Anthropic Claude (Orchestrator)

### Messages API - Conversational with Expert Synthesis

**Endpoint:** `POST https://api.anthropic.com/v1/messages`

**Headers:**
```
x-api-key: {ANTHROPIC_API_KEY}
anthropic-version: 2023-06-01
content-type: application/json
```

**Request:**
```json
{
  "model": "claude-sonnet-4-20250514",
  "max_tokens": 1024,
  "system": "You are a Magic: The Gathering deck building advisor with deep expertise across multiple domains.\n\nWhen answering questions, draw from your knowledge as:\n\n**Mana Base Expert**: You understand land counts, color sources, curve alignment, mana fixing needs, and color pip requirements. You can analyze whether a deck has enough mana sources for its curve and colors.\n\n**Synergy & Interactions Expert**: You identify card connections, non-obvious combos, enablers, and \"secret tech\". You understand what cards unlock other cards (e.g., \"Urza needs fast mana\").\n\n**Card Evaluation Expert**: You understand card roles in different contexts, can suggest upgrades, and explain why one card is better than another for specific purposes.\n\n**Meta & Matchups Expert**: You know the format metagame, popular decks, hate cards, and how to position against the field.\n\nWhen the question involves these topics, also consider:\n- **Win Condition Expert**: How the deck closes games, backup plans, inevitability\n- **Budget Expert**: Affordable alternatives when cost is mentioned\n- **Curve & Tempo Expert**: Turn-by-turn sequencing, mana efficiency\n- **Consistency Expert**: Redundancy, tutors, reliable execution\n- **Sideboard Expert**: 15-card construction, matchup-specific swaps\n- **Rules Expert**: Complex interactions, layers, triggers\n\nGuidelines:\n- Respond in a unified, conversational voice - don't say \"The mana expert suggests...\"\n- Weight perspectives by relevance to the specific question\n- Prioritize actionable insights over comprehensive analysis\n- Acknowledge trade-offs when different perspectives might conflict\n- Keep responses focused and helpful, not overwhelming",
  "messages": [
    {
      "role": "user",
      "content": "Context about this deck:\n- Format: Modern\n- Archetype: Control\n- Key Cards: Teferi, Hero of Dominaria; Supreme Verdict\n- Combos: None defined\n- Theme: UW Control focusing on planeswalker win conditions\n\nDeck Summary:\n- Mainboard: 58/60 cards\n- Sideboard: 12/15 cards\n- Mana Curve: 2/8/12/10/4/2 (by CMC 0-5+)\n- Colors: W: 20, U: 24\n- Avg Mana Value: 2.8\n- Lands: 24\n- Missing Key Cards: None\n- Incomplete Combos: None\n\nQuestion: What should I add to finish my mainboard?"
    }
  ]
}
```

**Response (Success):**
```json
{
  "id": "msg_01XFDUDYJgAACzvnptvVoYEL",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "With 58 cards and a solid UW Control shell, you have room for 2 more cards. Looking at your curve and the planeswalker theme, I'd suggest:\n\n1. **Shark Typhoon** - Incredibly flexible, works as both a threat and a cycling cantrip. It synergizes well with your planeswalker strategy since you can create tokens while holding up countermagic.\n\n2. **Castle Ardenvale** - Your land count is good at 24, and replacing a Plains with Castle Ardenvale gives you a late-game token generator that doesn't cost a spell slot.\n\nAlternatively, if you're facing a lot of creature decks in your meta, a second Supreme Verdict or a Wrath of God would shore up that matchup while staying on-theme with your control gameplan."
    }
  ],
  "model": "claude-sonnet-4-20250514",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 450,
    "output_tokens": 180
  }
}
```

---

## Error Codes

| Code | Type | Description | User Message |
|------|------|-------------|--------------|
| B001 | `card_not_found` | Card name not in database | "Card '{name}' not found. Did you mean...?" |
| B002 | `duplicate_key_card` | Card already in key cards | "'{name}' is already a key card" |
| B003 | `key_card_limit` | Over 10 key cards | "Maximum 10 key cards allowed" |
| B004 | `invalid_combo_size` | Combo not 2-4 cards | "Combos must have 2-4 cards" |
| B005 | `combo_limit` | Over 5 combos | "Maximum 5 combos allowed" |
| B006 | `theme_too_long` | Theme > 500 chars | "Theme must be 500 characters or less" |
| B007 | `invalid_archetype` | Unknown archetype value | "Invalid archetype" |
| B008 | `ai_unavailable` | AI API call failed | "Unable to analyze right now" |
| B009 | `index_out_of_bounds` | Invalid combo index | "Combo not found" |

---

## Rate Limits & Timeouts

| Operation | Timeout | Notes |
|-----------|---------|-------|
| AI Orchestrator call | 30 seconds | Sonnet responses can be longer |
| Card autocomplete | 200ms | Local PostgreSQL query |
| Brew update | 100ms | In-memory + localStorage |

**No user-facing rate limits** per Phase 2 pattern.

---

## Context Token Budget

| Component | Estimated Tokens | Notes |
|-----------|-----------------|-------|
| System prompt (experts) | ~800 | Fixed overhead |
| Brew context | ~150 | Archetype, key cards, combos, theme |
| Deck summary | ~200 | Stats, mana curve, colors |
| User question | ~50-200 | Varies |
| **Total Input** | ~1200-1400 | Well under limits |
| Response | ~200-500 | Keep concise per FR7.4 |

---

## HTTP Endpoints: Agent Configuration

### GET /admin/agents

List all agent configurations.

**Response:**
```json
{
  "agents": [
    {
      "id": "uuid",
      "agent_id": "orchestrator",
      "name": "Orchestrator",
      "description": "Synthesizes expert responses into unified voice",
      "provider": "anthropic",
      "model": "claude-sonnet-4-20250514",
      "system_prompt": "You are a Magic: The Gathering...",
      "max_tokens": 1024,
      "context_window": 200000,
      "temperature": 0.7,
      "enabled": true,
      "cost_per_1k_input": 0.003,
      "cost_per_1k_output": 0.015,
      "updated_at": "2026-01-04T00:00:00Z"
    },
    {
      "id": "uuid",
      "agent_id": "command_parser",
      "name": "Command Parser",
      "description": "Parses deck commands from natural language",
      "provider": "anthropic",
      "model": "claude-3-haiku-20240307",
      "system_prompt": "...",
      "max_tokens": 256,
      "context_window": 200000,
      "temperature": 0.0,
      "enabled": true,
      "cost_per_1k_input": 0.00025,
      "cost_per_1k_output": 0.00125,
      "updated_at": "2026-01-04T00:00:00Z"
    }
  ]
}
```

---

### GET /admin/agents/:agent_id

Get a specific agent configuration.

**Response:**
```json
{
  "agent": {
    "id": "uuid",
    "agent_id": "orchestrator",
    "name": "Orchestrator",
    "description": "Synthesizes expert responses into unified voice",
    "provider": "anthropic",
    "model": "claude-sonnet-4-20250514",
    "system_prompt": "You are a Magic: The Gathering deck building advisor...",
    "default_prompt": "You are a Magic: The Gathering deck building advisor...",
    "max_tokens": 1024,
    "context_window": 200000,
    "temperature": 0.7,
    "enabled": true,
    "cost_per_1k_input": 0.003,
    "cost_per_1k_output": 0.015,
    "inserted_at": "2026-01-04T00:00:00Z",
    "updated_at": "2026-01-04T00:00:00Z"
  }
}
```

**Errors:**
- 404: Agent not found

---

### PATCH /admin/agents/:agent_id

Update an agent configuration.

**Request:**
```json
{
  "agent": {
    "provider": "anthropic",
    "model": "claude-opus-4-20250514",
    "system_prompt": "Updated system prompt...",
    "max_tokens": 2048,
    "temperature": 0.5,
    "enabled": true
  }
}
```

**Notes:**
- Only provided fields are updated
- `agent_id`, `name`, `description`, `default_prompt` are immutable
- Validation ensures provider is valid enum
- Updates cached config in ETS

**Response:**
```json
{
  "agent": { /* updated agent object */ }
}
```

**Errors:**
- 400: Invalid parameters
- 404: Agent not found

---

### POST /admin/agents/:agent_id/reset

Reset an agent's system prompt to default.

**Request:** Empty body

**Response:**
```json
{
  "agent": { /* agent with system_prompt = default_prompt */ }
}
```

---

### GET /admin/agents/:agent_id/preview

Preview how a prompt would be formatted with sample context.

**Request:**
```json
{
  "sample_context": {
    "archetype": "control",
    "key_cards": ["Teferi, Hero of Dominaria"],
    "question": "What should I add?"
  }
}
```

**Response:**
```json
{
  "formatted_request": {
    "model": "claude-sonnet-4-20250514",
    "system": "You are a Magic: The Gathering...",
    "messages": [
      {
        "role": "user",
        "content": "Context about this deck:\n- Archetype: control\n..."
      }
    ],
    "max_tokens": 1024
  },
  "estimated_input_tokens": 1250,
  "estimated_cost": 0.00375
}
```

---

### GET /admin/providers

List available AI providers.

**Response:**
```json
{
  "providers": [
    {
      "id": "uuid",
      "provider": "anthropic",
      "api_key_env": "ANTHROPIC_API_KEY",
      "base_url": null,
      "enabled": true,
      "has_api_key": true,
      "models": [
        {"id": "claude-3-haiku-20240307", "name": "Claude 3 Haiku"},
        {"id": "claude-sonnet-4-20250514", "name": "Claude Sonnet 4"},
        {"id": "claude-opus-4-20250514", "name": "Claude Opus 4"}
      ]
    },
    {
      "id": "uuid",
      "provider": "openai",
      "api_key_env": "OPENAI_API_KEY",
      "base_url": null,
      "enabled": false,
      "has_api_key": false,
      "models": []
    }
  ]
}
```

**Notes:**
- `has_api_key` indicates if environment variable is set (never exposes key)
- `models` list filtered by what's available for that provider

---

### PATCH /admin/providers/:provider

Update provider configuration.

**Request:**
```json
{
  "provider": {
    "api_key_env": "MY_ANTHROPIC_KEY",
    "base_url": "https://custom-proxy.example.com/v1",
    "enabled": true
  }
}
```

**Response:**
```json
{
  "provider": { /* updated provider config */ }
}
```

---

## LiveView: Agent Config UI

### Route: `/admin/agents`

**LiveView:** `MtgDeckBuilderWeb.Admin.AgentsLive`

**Features:**
- List all agents with current model/status
- Click agent to edit
- Inline editing of system prompt (code editor)
- Model selector dropdown (filtered by provider)
- Temperature slider (0.0 - 2.0)
- Enable/disable toggle
- Reset to default button
- Estimated cost per request display
- Preview button to test prompt formatting

---

## Provider Adapters

### Anthropic Adapter

Formats requests for Anthropic Claude API.

**Request Format:**
```json
{
  "model": "claude-sonnet-4-20250514",
  "system": "System prompt here...",
  "messages": [
    {"role": "user", "content": "User message"}
  ],
  "max_tokens": 1024,
  "temperature": 0.7
}
```

**Notes:**
- System prompt as separate `system` parameter
- Messages array for conversation history

---

### OpenAI Adapter

Formats requests for OpenAI API.

**Request Format:**
```json
{
  "model": "gpt-4-turbo",
  "messages": [
    {"role": "system", "content": "System prompt here..."},
    {"role": "user", "content": "User message"}
  ],
  "max_tokens": 1024,
  "temperature": 0.7
}
```

**Notes:**
- System prompt as first message with `role: "system"`
- Follows OpenAI message format convention

---

### xAI Adapter (Grok)

Formats requests for xAI Grok API.

**Request Format:**
```json
{
  "model": "grok-2",
  "messages": [
    {"role": "system", "content": "System prompt here..."},
    {"role": "user", "content": "User message"}
  ],
  "max_tokens": 1024,
  "temperature": 0.7
}
```

**Notes:**
- Similar to OpenAI format
- Uses xAI-specific model identifiers

---

## Agent Config Error Codes

| Code | Type | Description | User Message |
|------|------|-------------|--------------|
| AC001 | `agent_not_found` | Agent ID doesn't exist | "Agent not found" |
| AC002 | `invalid_provider` | Provider not in enum | "Invalid provider" |
| AC003 | `invalid_model` | Model not available for provider | "Model not available" |
| AC004 | `invalid_temperature` | Temperature out of range | "Temperature must be between 0.0 and 2.0" |
| AC005 | `provider_disabled` | Provider is disabled | "Provider is not enabled" |
| AC006 | `no_api_key` | API key env var not set | "API key not configured for provider"
