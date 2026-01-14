# Quickstart: MTG Deck Builder MVP

**Feature:** 1-mtg-deck-builder-mvp
**Date:** 2026-01-03

## Prerequisites

- Elixir 1.15+
- Erlang/OTP 26+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)

## Setup

```bash
# Clone and enter directory
cd mtg_deck_builder

# Install dependencies
mix deps.get

# Create and migrate database
mix ecto.setup

# Install Node dependencies
cd assets && npm install && cd ..

# Start Phoenix server
mix phx.server
```

Open http://localhost:4000

## Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
# Database
DATABASE_URL=postgres://postgres:postgres@localhost/mtg_deck_builder_dev

# Optional: Override Scryfall base URL for testing
# SCRYFALL_BASE_URL=https://api.scryfall.com
```

## Development

```bash
# Run tests
mix test

# Run Credo linter
mix credo

# Run Dialyzer (first run is slow)
mix dialyzer

# Format code
mix format

# Interactive console
iex -S mix
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `MtgDeckBuilder.Cards` | Card search and caching context |
| `MtgDeckBuilder.Cards.ScryfallClient` | Scryfall API client |
| `MtgDeckBuilder.Decks.Validator` | Format validation logic |
| `MtgDeckBuilder.Decks.Stats` | Deck statistics calculation |
| `MtgDeckBuilderWeb.DeckLive` | Main deck editor LiveView |

## Testing the Scryfall Client

```elixir
# In iex -S mix
alias MtgDeckBuilder.Cards

# Search for cards
Cards.search("lightning bolt")

# Get specific card
Cards.get_by_name("Lightning Bolt")
```

## LiveView Development

The main deck editor is at `/` and uses these hooks:

- `SearchDebounce` - Debounces search input (300ms)
- `DeckStorage` - Syncs deck to/from localStorage

To test localStorage sync:
1. Add cards to deck
2. Refresh page
3. Deck should persist

## Format Validation Testing

```elixir
# In iex -S mix
alias MtgDeckBuilder.Decks.Validator

# Check if card is legal
Validator.legal?("abc123-scryfall-id", :modern)

# Validate entire deck
Validator.validate_deck(deck, :modern)
```

## Troubleshooting

**Search not working?**
- Check Scryfall API is reachable: `curl https://api.scryfall.com/cards/search?q=bolt`
- Check rate limiting (100ms between requests)

**Deck not persisting?**
- Check browser console for localStorage errors
- Verify `DeckStorage` hook is connected

**Cards showing as illegal?**
- Verify format selection matches expected legality
- Check Scryfall's legalities data for the card
