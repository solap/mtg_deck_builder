# API Contracts: AI Chat Commands

**Feature:** 2-ai-chat-commands
**Date:** 2026-01-04

## Overview

This feature primarily uses LiveView events (not REST endpoints). The only HTTP endpoint is the admin cost dashboard. External API integration is with Anthropic Claude.

---

## LiveView Events

### Client → Server Events

#### 1. `submit_command`

User submits a chat command for processing.

**Payload:**
```elixir
%{
  "command" => "add 4 lightning bolt to mainboard"  # string, max 500 chars
}
```

**Responses:**
- Success: Pushes `command_result` event to client
- Error: Pushes `command_error` event to client

**Example:**
```javascript
// Client
this.pushEvent("submit_command", {command: "add 4 lightning bolt"})
```

---

#### 2. `select_card`

User selects from disambiguation options.

**Payload:**
```elixir
%{
  "selection_index" => 1  # integer, 1-based index from options list
}
```

**Responses:**
- Success: Executes command with selected card
- Error: Shows error if index invalid

---

#### 3. `navigate_history`

User navigates command history with arrow keys.

**Payload:**
```elixir
%{
  "direction" => "up"  # "up" | "down"
}
```

**Response:**
- Updates input field with historical command

---

#### 4. `clear_chat`

User clears chat history.

**Payload:** (none)

**Response:**
- Clears chat messages in LiveView assigns
- Triggers `sync_chat` to update localStorage

---

### Server → Client Events

#### 1. `command_result`

Successful command execution result.

**Payload:**
```elixir
%{
  "message" => "Added 4x Lightning Bolt to mainboard",
  "action" => "add",
  "affected_cards" => [
    %{
      "name" => "Lightning Bolt",
      "quantity" => 4,
      "board" => "mainboard"
    }
  ],
  "deck_valid" => true
}
```

---

#### 2. `command_error`

Command failed to execute.

**Payload:**
```elixir
%{
  "message" => "Cannot add 5th copy of Lightning Bolt (max 4)",
  "error_type" => "copy_limit",  # copy_limit | not_found | format_illegal | api_error | invalid_command
  "suggestions" => ["Current count: 4"]
}
```

---

#### 3. `card_disambiguation`

Multiple cards match, user must select.

**Payload:**
```elixir
%{
  "message" => "Multiple cards match 'bolt'. Which did you mean?",
  "options" => [
    %{"index" => 1, "name" => "Lightning Bolt", "set" => "M21"},
    %{"index" => 2, "name" => "Lava Bolt", "set" => "TST"},
    %{"index" => 3, "name" => "Bolt of Flame", "set" => "XYZ"}
  ]
}
```

---

#### 4. `sync_chat`

Sync chat history to localStorage.

**Payload:**
```elixir
%{
  "messages" => [
    %{
      "id" => "uuid",
      "role" => "user",
      "content" => "add 4 lightning bolt",
      "timestamp" => "2026-01-04T12:00:00Z"
    },
    %{
      "id" => "uuid",
      "role" => "assistant",
      "content" => "Added 4x Lightning Bolt to mainboard",
      "timestamp" => "2026-01-04T12:00:01Z"
    }
  ]
}
```

---

#### 5. `ai_processing`

Show/hide loading state during AI call.

**Payload:**
```elixir
%{
  "processing" => true  # boolean
}
```

---

## HTTP Endpoints

### Admin Cost Dashboard

#### GET /admin/costs

Returns HTML page (LiveView) showing API usage costs.

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| from | date | 7 days ago | Start date (YYYY-MM-DD) |
| to | date | today | End date (YYYY-MM-DD) |
| provider | string | all | Filter by provider |

**Response:** HTML page with cost breakdown

---

#### GET /api/admin/costs

JSON API for programmatic access (optional).

**Query Parameters:** Same as above

**Response:**
```json
{
  "period": {
    "from": "2026-01-01",
    "to": "2026-01-04"
  },
  "totals": {
    "requests": 1250,
    "input_tokens": 125000,
    "output_tokens": 62500,
    "cost_cents": 312
  },
  "by_provider": {
    "anthropic": {
      "requests": 1200,
      "input_tokens": 120000,
      "output_tokens": 60000,
      "cost_cents": 300
    },
    "openai": {
      "requests": 50,
      "input_tokens": 5000,
      "output_tokens": 2500,
      "cost_cents": 12
    }
  },
  "by_day": [
    {
      "date": "2026-01-04",
      "requests": 450,
      "cost_cents": 112
    }
  ]
}
```

---

## External API: Anthropic Claude

### Messages API with Tool Use

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
  "model": "claude-3-haiku-20240307",
  "max_tokens": 256,
  "tools": [
    {
      "name": "deck_command",
      "description": "Parse a Magic: The Gathering deck building command. Extract the action, card name, quantity, and target board from natural language input.",
      "input_schema": {
        "type": "object",
        "properties": {
          "action": {
            "type": "string",
            "enum": ["add", "remove", "set", "move", "query", "undo", "help"],
            "description": "The deck operation to perform"
          },
          "card_name": {
            "type": "string",
            "description": "The name of the card (as close to user input as possible)"
          },
          "quantity": {
            "type": "integer",
            "minimum": 1,
            "maximum": 15,
            "description": "Number of cards (default 1 if not specified)"
          },
          "source_board": {
            "type": "string",
            "enum": ["mainboard", "sideboard"],
            "description": "Board to take cards from (for move/remove)"
          },
          "target_board": {
            "type": "string",
            "enum": ["mainboard", "sideboard"],
            "description": "Board to put cards in (default mainboard)"
          },
          "query_type": {
            "type": "string",
            "enum": ["count", "list", "status"],
            "description": "Type of query for query actions"
          }
        },
        "required": ["action"]
      }
    }
  ],
  "tool_choice": {"type": "tool", "name": "deck_command"},
  "messages": [
    {
      "role": "user",
      "content": "add 4 lightning bolt"
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
      "type": "tool_use",
      "id": "toolu_01A09q90qw90lq917835lq",
      "name": "deck_command",
      "input": {
        "action": "add",
        "card_name": "lightning bolt",
        "quantity": 4,
        "target_board": "mainboard"
      }
    }
  ],
  "model": "claude-3-haiku-20240307",
  "stop_reason": "tool_use",
  "usage": {
    "input_tokens": 125,
    "output_tokens": 45
  }
}
```

**Error Responses:**
- 400: Invalid request
- 401: Invalid API key
- 429: Rate limited
- 500: Server error
- 529: API overloaded

---

## Error Codes

| Code | Type | Description | User Message |
|------|------|-------------|--------------|
| E001 | `invalid_command` | Unrecognized command structure | "I didn't understand that. Try 'add 4 lightning bolt'" |
| E002 | `card_not_found` | No matching card in database | "No card found matching '{name}'. Did you mean...?" |
| E003 | `copy_limit` | Exceeds 4-copy rule | "Cannot add {n}th copy (max 4 for non-basic lands)" |
| E004 | `format_illegal` | Card not legal in format | "{card} is not legal in {format}" |
| E005 | `sideboard_full` | Sideboard > 15 cards | "Sideboard is full (15/15 cards)" |
| E006 | `card_not_in_deck` | Remove/move card not present | "{card} is not in your {board}" |
| E007 | `api_unavailable` | AI API call failed | "AI temporarily unavailable, please use UI controls" |
| E008 | `nothing_to_undo` | Undo with empty history | "Nothing to undo" |
| E009 | `restricted_limit` | Vintage restricted card | "{card} is restricted in Vintage (max 1 copy)" |

---

## Rate Limits & Timeouts

| Operation | Timeout | Notes |
|-----------|---------|-------|
| AI API call | 10 seconds | User sees loading indicator |
| Card DB search | 500ms | Local PostgreSQL |
| Command execution | 100ms | In-memory deck modification |

**No user-facing rate limits** per clarification. API provider rate limits handled with error message.
