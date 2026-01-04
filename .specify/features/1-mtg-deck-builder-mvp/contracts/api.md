# API Contracts: MTG Deck Builder MVP

**Feature:** 1-mtg-deck-builder-mvp
**Date:** 2026-01-03

## Overview

MVP uses Phoenix LiveView - no traditional REST API needed. All interactions happen via LiveView events and server-side state.

This document defines the **LiveView event contracts** and **Scryfall API integration**.

---

## LiveView Events

### DeckLive (Main Deck Editor)

**Module:** `MtgDeckBuilderWeb.DeckLive`

#### Events: Client → Server

| Event | Payload | Description |
|-------|---------|-------------|
| `search_cards` | `%{"query" => string}` | Trigger card search |
| `add_card` | `%{"scryfall_id" => string, "board" => "mainboard"\|"sideboard", "quantity" => integer}` | Add card to deck |
| `remove_card` | `%{"scryfall_id" => string, "board" => "mainboard"\|"sideboard"}` | Remove card entirely |
| `update_quantity` | `%{"scryfall_id" => string, "board" => string, "delta" => integer}` | Change quantity (+1/-1) |
| `move_card` | `%{"scryfall_id" => string, "from" => string, "to" => string, "quantity" => integer}` | Move between boards |
| `change_format` | `%{"format" => string}` | Switch deck format |
| `restore_card` | `%{"scryfall_id" => string, "board" => "mainboard"\|"sideboard"}` | Restore from removed |
| `set_deck_name` | `%{"name" => string}` | Rename deck |
| `clear_deck` | `%{}` | Clear all cards |
| `load_deck` | `%{"deck_json" => string}` | Load from localStorage |

#### Assigns: Server → Client

```elixir
%{
  deck: %Deck{
    id: string,
    name: string,
    format: atom,
    mainboard: [%DeckCard{}],
    sideboard: [%DeckCard{}],
    removed_cards: [%RemovedCard{}]
  },
  search_results: [%SearchResult{}],
  search_query: string,
  search_loading: boolean,
  stats: %DeckStats{
    total_cards: integer,
    mana_curve: map,
    color_distribution: map,
    type_breakdown: map,
    average_mv: float,
    is_valid: boolean,
    validation_errors: [string]
  },
  flash: %{error: string | nil, info: string | nil}
}
```

---

## LiveView Event Handlers

### search_cards

```elixir
def handle_event("search_cards", %{"query" => query}, socket) when byte_size(query) >= 2 do
  # Debounced on client side (300ms)
  # 1. Call Scryfall API (or cache)
  # 2. Filter by format legality
  # 3. Update search_results assign
end
```

**Validation:**
- Query must be at least 2 characters
- Rate limit: queue if <100ms since last call

**Response:**
- Success: Updates `search_results` with filtered cards
- No results: `search_results = []`, flash info message
- API error: `search_results = []`, flash error message

---

### add_card

```elixir
def handle_event("add_card", %{"scryfall_id" => id, "board" => board, "quantity" => qty}, socket) do
  # 1. Validate card is legal in format
  # 2. Validate quantity rules (4 max, except basic lands)
  # 3. Add to appropriate list
  # 4. Recalculate stats
  # 5. Sync to localStorage via push_event
end
```

**Validation:**
- Card must be legal in current format
- Total copies across boards ≤ 4 (unless basic land)
- Sideboard cannot exceed 15 cards
- Quantity must be positive integer

**Response:**
- Success: Updates deck, stats, push_event to sync localStorage
- Illegal card: Flash error with reason
- Over limit: Flash error with explanation

---

### change_format

```elixir
def handle_event("change_format", %{"format" => format}, socket) do
  # 1. Set new format
  # 2. Check each card's legality in new format
  # 3. Move illegal cards to removed_cards with reason
  # 4. Flash notification if cards were moved
  # 5. Recalculate stats
end
```

**Response:**
- Cards moved: Flash info "X cards moved to Removed Cards"
- No changes needed: Silent success
- Invalid format: Flash error

---

## Scryfall API Integration

### Base URL
```
https://api.scryfall.com
```

### Rate Limiting
- Maximum 10 requests/second
- Minimum 100ms between requests
- Implement request queue if needed

### Endpoints Used

#### GET /cards/search

Search for cards by name.

**Request:**
```
GET /cards/search?q={query}&unique=cards&order=name
```

**Query Parameters:**
- `q`: Search query (supports Scryfall syntax)
- `unique`: `cards` - deduplicate printings
- `order`: `name` - alphabetical

**Response (200):**
```json
{
  "object": "list",
  "total_cards": 42,
  "has_more": false,
  "data": [
    {
      "id": "abc123",
      "name": "Lightning Bolt",
      "mana_cost": "{R}",
      "cmc": 1.0,
      "type_line": "Instant",
      "oracle_text": "Lightning Bolt deals 3 damage to any target.",
      "colors": ["R"],
      "color_identity": ["R"],
      "legalities": {
        "standard": "not_legal",
        "modern": "legal",
        "pioneer": "not_legal",
        "legacy": "legal",
        "vintage": "legal",
        "pauper": "legal"
      },
      "prices": {
        "usd": "1.50",
        "usd_foil": "3.00"
      },
      "image_uris": {
        "small": "https://cards.scryfall.io/small/...",
        "normal": "https://cards.scryfall.io/normal/...",
        "large": "https://cards.scryfall.io/large/..."
      }
    }
  ]
}
```

**Error Responses:**
- `400`: Invalid query syntax
- `404`: No cards found
- `429`: Rate limited

---

#### GET /cards/named

Get single card by exact or fuzzy name.

**Request:**
```
GET /cards/named?fuzzy={name}
```

**Response:** Same structure as search, single card object

---

## Client-Side Storage Contract

### localStorage Key
```
mtg_deck_builder_deck
```

### Value Format (JSON)
```json
{
  "id": "uuid-v4",
  "name": "My Modern Deck",
  "format": "modern",
  "mainboard": [
    {
      "scryfallId": "abc123",
      "name": "Lightning Bolt",
      "quantity": 4,
      "manaCost": "{R}",
      "cmc": 1,
      "typeLine": "Instant",
      "colors": ["R"],
      "imageUri": "https://...",
      "priceUsd": "1.50"
    }
  ],
  "sideboard": [],
  "removedCards": [],
  "createdAt": "2026-01-03T12:00:00Z",
  "updatedAt": "2026-01-03T12:30:00Z"
}
```

### Sync Events

**Server → Client (push_event):**
```elixir
push_event(socket, "sync_deck", %{deck_json: Jason.encode!(deck)})
```

**Client → Server (on page load):**
```javascript
// In app.js hook
this.pushEvent("load_deck", {deck_json: localStorage.getItem("mtg_deck_builder_deck")})
```

---

## Error Codes

| Code | Message | Cause |
|------|---------|-------|
| `card_not_legal` | "Card is not legal in {format}" | Adding banned/not_legal card |
| `max_copies` | "Maximum 4 copies allowed" | Exceeding 4-copy limit |
| `sideboard_full` | "Sideboard cannot exceed 15 cards" | Adding 16th sideboard card |
| `search_failed` | "Card search failed, please try again" | Scryfall API error |
| `invalid_format` | "Invalid format selected" | Unknown format string |
