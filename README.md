# MTG Deck Builder

A Magic: The Gathering deck building application built with Phoenix LiveView.

## Features

- **Card Search**: Search over 36,000+ cards from Scryfall's oracle cards database
- **Format Filtering**: Filter cards by format legality (Standard, Modern, Pioneer, Legacy, Vintage, Pauper)
- **Deck Building**: Add cards to mainboard and sideboard with quantity management
- **Format Validation**: Automatic illegal card detection when switching formats
- **Deck Statistics**: Real-time mana curve, color distribution, type breakdown, and price totals
- **Local Persistence**: Deck state saved to browser localStorage

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

3. Import card data from Scryfall (~2-3 minutes):
   ```bash
   mix cards.import
   ```

4. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

5. Visit [`localhost:4000`](http://localhost:4000)

## Card Data

Card data is imported from [Scryfall](https://scryfall.com)'s bulk data API. The `oracle_cards` dataset contains one entry per unique card (~36,000 cards).

To sync card data (for ban list updates):
```bash
mix cards.sync
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

## Architecture

- **Backend**: Elixir + Phoenix LiveView
- **Database**: PostgreSQL with full-text search (pg_trgm)
- **Frontend**: Phoenix LiveView + Tailwind CSS
- **Card Data**: Scryfall bulk data (local database)
- **Session Storage**: Browser localStorage

## License

MIT
