# MTG Deck Builder

A Magic: The Gathering deck building application built with Phoenix LiveView.

**Live Demo**: https://mtg-deck-builder-mvp.fly.dev

## Features

- **Card Search**: Search over 36,000+ cards from Scryfall's oracle cards database
- **Format Filtering**: Filter cards by format legality (Standard, Modern, Pioneer, Legacy, Vintage, Pauper)
- **Deck Building**: Add cards to mainboard and sideboard with quantity management
- **Format Validation**: Automatic illegal card detection when switching formats
- **Deck Statistics**: Real-time mana curve, color distribution, type breakdown, and price totals
- **Local Persistence**: Deck state saved to browser localStorage
- **AI Chat Commands**: Natural language deck building (e.g., "add 4 lightning bolt")

## AI Chat Commands

The deck builder supports natural language commands for quick deck editing. Just type in the chat input:

### Adding Cards
```
add 4 lightning bolt           # Add 4 to mainboard
add 2 counterspell to sideboard
add AOTG                       # Acronyms work too (Anger of the Gods)
```

### Removing Cards
```
remove lightning bolt          # Remove all copies
remove 2 lightning bolt        # Remove 2 copies
remove counterspell from sideboard
```

### Updating Quantities
```
set lightning bolt to 3        # Set exact quantity
add 1 more lightning bolt      # Increment by 1
```

### Moving Cards
```
move 2 lightning bolt to sideboard
move counterspell to mainboard
move all bolts to staging      # Staging area for cards being considered
```

### Querying Deck Status
```
how many lightning bolt        # Check card count
show mainboard                 # List mainboard cards
deck status                    # Overall deck summary
```

### Other Commands
```
undo                          # Undo last chat action
help                          # Show available commands
```

### Tips
- Card names are fuzzy-matched (typos are OK)
- Common MTG acronyms are recognized (BBE, SFM, JtMS, etc.)
- Default board is mainboard, default quantity is 1
- Use "/" keyboard shortcut to focus chat input

## Setup

### Prerequisites

- Elixir 1.14+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)

### Installation

1. Install dependencies:
   ```bash
   mix deps.get
   ```

2. Create and migrate database:
   ```bash
   mix ecto.setup
   ```

3. Import card data from Scryfall (~30 seconds with COPY):
   ```bash
   mix cards.import
   ```

4. Set up environment variables (for AI features):
   ```bash
   cp .env.example .env.local
   # Edit .env.local and add your ANTHROPIC_API_KEY
   ```

5. Start the Phoenix server:
   ```bash
   bin/dev
   ```
   This script loads `.env.local` and starts the server. Alternatively: `mix phx.server`

6. Visit [`localhost:4000`](http://localhost:4000)

## Card Data Architecture

Card data is sourced from [Scryfall](https://scryfall.com)'s bulk data API (`oracle_cards` - ~36,000 unique cards, 166MB JSON).

### High-Performance Import with PostgreSQL COPY

We use PostgreSQL's COPY protocol instead of INSERT for 10-100x faster imports:

```
Scryfall JSON (166MB)
    ↓ hackney (streaming download)
Temp file
    ↓ Jaxon (streaming JSON parse)
CSV rows
    ↓ Postgrex COPY protocol
PostgreSQL
```

**Performance**: ~36,000 cards imported in ~11 seconds (vs minutes with INSERT)

### Key Components

| Module | Purpose |
|--------|---------|
| `Cards.CopyImporter` | High-performance COPY-based import |
| `Cards.CardSyncWorker` | Scheduled daily sync (GenServer) |
| `Cards.BulkImporter` | Legacy INSERT-based import |

### Automatic Sync

The `CardSyncWorker` handles card data automatically:

- **On first deploy** (empty DB): Auto-imports after 30s delay
- **Daily sync**: Refreshes prices/legalities every 24 hours
- **Manual trigger**: `CardSyncWorker.sync_now()`

### Why COPY over INSERT?

| Approach | Speed | Memory | Reliability |
|----------|-------|--------|-------------|
| INSERT (individual) | ~100 rows/sec | Low | Timeouts |
| INSERT (batch) | ~500 rows/sec | Medium | Pool exhaustion |
| **COPY protocol** | **~3,300 rows/sec** | Low | Dedicated connection |

COPY bypasses SQL parsing, batches WAL writes, and uses a dedicated connection to avoid pool contention.

## Production Deployment (Fly.io)

### Initial Deploy

```bash
fly launch
fly postgres create --name mtg-deck-builder-mvp-db
fly postgres attach mtg-deck-builder-mvp-db
fly deploy
```

The app will auto-import cards on first boot (wait ~30s after deploy).

### Manual Card Sync

```bash
fly ssh console -C '/app/bin/mtg_deck_builder rpc "MtgDeckBuilder.Cards.CardSyncWorker.sync_now()"'
```

### Check Card Count

```bash
fly ssh console -C '/app/bin/mtg_deck_builder rpc "IO.puts(MtgDeckBuilder.Cards.count())"'
```

### Configuration

```toml
# fly.toml
[[vm]]
  memory = '2gb'  # Required for card import
  cpu_kind = 'shared'
  cpus = 1
```

## Development

### Running Tests

```bash
mix test
```

### Code Quality

```bash
mix credo --strict
mix dialyzer
```

### Useful IEx Commands

```elixir
# Search cards
MtgDeckBuilder.Cards.search("lightning bolt", format: :modern)

# Card count
MtgDeckBuilder.Cards.count()

# Check sync status
MtgDeckBuilder.Cards.CardSyncWorker.status()

# Manual sync
MtgDeckBuilder.Cards.CardSyncWorker.sync_now()
```

## Architecture

- **Backend**: Elixir + Phoenix LiveView
- **Database**: PostgreSQL with trigram search (pg_trgm)
- **Frontend**: Phoenix LiveView + Tailwind CSS
- **Card Data**: Scryfall bulk data with COPY import
- **Deployment**: Fly.io with Postgres
- **Session Storage**: Browser localStorage

## Tech Stack

| Component | Technology |
|-----------|------------|
| Runtime | Elixir 1.18 / OTP 27 |
| Web Framework | Phoenix 1.7 / LiveView 1.0 |
| Database | PostgreSQL 17 |
| HTTP Client | Tesla + Hackney |
| JSON Parsing | Jason (general) / Jaxon (streaming) |
| Hosting | Fly.io |

## License

MIT
