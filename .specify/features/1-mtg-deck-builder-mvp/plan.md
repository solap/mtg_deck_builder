# Implementation Plan: MTG Deck Builder MVP

**Feature:** 1-mtg-deck-builder-mvp
**Version:** 2.0.0
**Date:** 2026-01-03
**Branch:** `1-mtg-deck-builder-mvp`

## Technical Context

| Aspect | Decision | Reference |
|--------|----------|-----------|
| Backend | Elixir + Phoenix | Constitution: Boring Technology |
| Frontend | Phoenix LiveView | research.md |
| Database | PostgreSQL | Constitution: Boring Technology |
| Card Data | Scryfall bulk data (oracle-cards) | spec.md v2.3.0 |
| Card Display | Text-only (no images in MVP) | spec.md v2.3.0 |
| HTTP Client | Tesla | For bulk data download |
| Deck Storage | localStorage | spec.md |
| Data Sync | Daily/weekly bulk sync | spec.md v2.3.0 |

## Constitution Compliance

| Principle | Status | Implementation |
|-----------|--------|----------------|
| Incremental Delivery | ✅ | 6 testable increments below |
| AI-Native Architecture | N/A | No AI in MVP |
| Boring Technology | ✅ | Standard Phoenix/LiveView patterns |
| Working Code Over Perfect | ✅ | localStorage, no auth, text-only UI |

## Architecture Overview

```
Scryfall Bulk Data (oracle-cards.json, ~27k cards, ~25MB)
                    ↓
            [Mix Task: Import]
                    ↓
        PostgreSQL (cards table - complete DB)
                    ↓
            [Daily/Weekly Sync Task]
                    ↓
        Local Search (fast, no rate limits)
                    ↓
        LiveView UI (text-only display)
```

## Implementation Increments

Each increment is independently testable before proceeding.

### Increment 1: Project Setup
**Test:** Phoenix app runs, connects to DB, loads homepage

**Tasks:**
1. Create Phoenix project with `mix phx.new`
2. Configure PostgreSQL database
3. Set up Tailwind CSS
4. Create basic layout with header/footer
5. Add homepage LiveView with placeholder content
6. Configure environment variables (.env.example)

**Artifacts:**
- `mix.exs` with dependencies
- `config/dev.exs`, `config/test.exs`, `config/runtime.exs`
- `lib/mtg_deck_builder_web/router.ex`
- `lib/mtg_deck_builder_web/live/home_live.ex`

**Acceptance:** `mix phx.server` starts, http://localhost:4000 loads

---

### Increment 2: Bulk Data Import & Card Database
**Test:** Run mix task, see ~27k cards in database, search works locally

**Tasks:**
1. Create `Card` schema with all fields (name, mana_cost, cmc, type_line, oracle_text, colors, legalities, prices, etc.)
2. Create migration for cards table with appropriate indexes
3. Create `MtgDeckBuilder.Cards.BulkImporter` module
4. Implement bulk data download from Scryfall (oracle-cards.json)
5. Implement JSON parsing and batch insert (~1000 cards per batch)
6. Create mix task `mix cards.import` to run initial import
7. Implement `Cards.search/1` with PostgreSQL full-text search or ILIKE
8. Implement `Cards.get_by_id/1` for card lookup
9. Add index on name column for fast search
10. Write tests for importer and search

**Artifacts:**
- `lib/mtg_deck_builder/cards/card.ex` schema
- `lib/mtg_deck_builder/cards/cards.ex` context
- `lib/mtg_deck_builder/cards/bulk_importer.ex`
- `lib/mix/tasks/cards.import.ex`
- `priv/repo/migrations/*_create_cards.exs`
- `test/mtg_deck_builder/cards/` tests

**Acceptance:**
```bash
mix cards.import
# Downloads ~25MB, imports ~27k cards

iex> MtgDeckBuilder.Cards.search("lightning bolt")
# Returns Lightning Bolt instantly from local DB
```

---

### Increment 3: Card Search UI (Text-Only)
**Test:** Type card name, see text-based card info displayed

**Tasks:**
1. Create `DeckLive` LiveView for main deck editor
2. Add search input with debounce (300ms)
3. Display search results as text-based card list
4. Show card name, mana cost, type, oracle text, price (NO images)
5. Add card detail expansion on click (shows full oracle text)
6. Filter results by format legality (default: Modern)
7. Implement fuzzy search ranking (closest matches first)

**Artifacts:**
- `lib/mtg_deck_builder_web/live/deck_live.ex`
- `lib/mtg_deck_builder_web/live/deck_live.html.heex`
- `lib/mtg_deck_builder_web/components/card_component.ex`
- `assets/js/hooks/search_debounce.js`

**Acceptance:** Search "bolt", see Lightning Bolt with text info (name, {R}, Instant, "deals 3 damage")

---

### Increment 4: Deck List Management
**Test:** Add cards, see them in list, adjust quantities, persist to localStorage

**Tasks:**
1. Add mainboard/sideboard sections to UI
2. Implement "Add to Mainboard/Sideboard" buttons
3. Display deck list with card info and quantity
4. Add +/- buttons for quantity adjustment
5. Add remove button
6. Add move between boards functionality
7. Implement localStorage persistence via JS hooks
8. Sync LiveView state from localStorage on load

**Artifacts:**
- Updates to `deck_live.ex` and template
- `lib/mtg_deck_builder_web/components/deck_list_component.ex`
- `assets/js/hooks/deck_storage.js`

**Acceptance:** Add 4 Lightning Bolts, refresh page, still there

---

### Increment 5: Format Validation & Switching
**Test:** Change format, illegal cards move to Removed Cards

**Tasks:**
1. Add format selector dropdown (Standard, Modern, Pioneer, Legacy, Vintage, Pauper)
2. Validate card legality on add (reject with error)
3. Enforce 4-copy maximum (except basic lands)
4. Enforce 1-copy maximum for restricted cards in Vintage
5. Enforce sideboard 15-card maximum
6. Implement format switch with illegal card handling
7. Create "Removed Cards" section with restore option
8. Show deck validity status (legal/illegal)

**Artifacts:**
- Updates to `deck_live.ex`
- `lib/mtg_deck_builder/decks/validator.ex`
- `lib/mtg_deck_builder_web/components/removed_cards_component.ex`

**Acceptance:**
- Build Modern deck with Lightning Bolt
- Switch to Standard
- Lightning Bolt moves to Removed Cards with reason "not_legal"

---

### Increment 6: Deck Statistics & Data Sync
**Test:** See mana curve, color distribution update in real-time; sync task updates bans

**Tasks:**
1. Create stats panel component
2. Implement mana curve calculation and display (text/bars)
3. Implement color distribution calculation and display
4. Implement type breakdown calculation and display
5. Calculate average mana value (excluding lands)
6. Ensure stats update <500ms on any deck change
7. Create `MtgDeckBuilder.Cards.BulkSync` module for incremental updates
8. Create mix task `mix cards.sync` for daily/weekly sync
9. Implement diff logic: compare bulk data to DB, update changed cards only
10. Log sync results (cards added, updated, legality changes)

**Artifacts:**
- `lib/mtg_deck_builder/decks/stats.ex`
- `lib/mtg_deck_builder_web/components/stats_component.ex`
- `lib/mtg_deck_builder/cards/bulk_sync.ex`
- `lib/mix/tasks/cards.sync.ex`

**Acceptance:**
- Add cards to deck, see mana curve bars update immediately
- Run `mix cards.sync`, see "X cards updated, Y legality changes"

---

## File Structure

```
mtg_deck_builder/
├── lib/
│   ├── mtg_deck_builder/
│   │   ├── cards/
│   │   │   ├── cards.ex           # Context (search, get)
│   │   │   ├── card.ex            # Schema (full card data)
│   │   │   ├── bulk_importer.ex   # Initial import from Scryfall
│   │   │   └── bulk_sync.ex       # Incremental sync for bans/new cards
│   │   ├── decks/
│   │   │   ├── deck.ex            # Struct (not DB)
│   │   │   ├── deck_card.ex       # Card-in-deck struct
│   │   │   ├── validator.ex       # Format validation
│   │   │   └── stats.ex           # Statistics calculation
│   │   └── application.ex
│   ├── mtg_deck_builder_web/
│   │   ├── live/
│   │   │   └── deck_live.ex       # Main LiveView
│   │   ├── components/
│   │   │   ├── card_component.ex
│   │   │   ├── deck_list_component.ex
│   │   │   ├── stats_component.ex
│   │   │   └── removed_cards_component.ex
│   │   ├── router.ex
│   │   └── layouts/
│   └── mix/
│       └── tasks/
│           ├── cards.import.ex    # mix cards.import
│           └── cards.sync.ex      # mix cards.sync
├── assets/
│   ├── js/
│   │   └── hooks/
│   │       ├── search_debounce.js
│   │       └── deck_storage.js
│   └── css/
├── priv/
│   └── repo/migrations/
├── test/
│   ├── mtg_deck_builder/
│   │   └── cards/
│   └── mtg_deck_builder_web/
│       └── live/
└── config/
```

---

## Dependencies

```elixir
# mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:phoenix_html, "~> 4.0"},
    {:phoenix_ecto, "~> 4.4"},
    {:ecto_sql, "~> 3.10"},
    {:postgrex, ">= 0.0.0"},
    {:tesla, "~> 1.7"},           # HTTP client for bulk download
    {:jason, "~> 1.4"},           # JSON parsing
    {:tailwind, "~> 0.2"},
    {:esbuild, "~> 0.8"},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Bulk download fails | Can't populate card DB | Retry logic, partial resume, fallback URL |
| Large import is slow | Bad first-run experience | Batch inserts, progress indicator, ~2-3 min expected |
| Sync misses ban announcement | Illegal deck shown as legal | Daily sync default, manual sync option |
| localStorage limit | Can't save large decks | Deck is ~10KB, well under 5MB limit |
| Browser compatibility | UI breaks | Test on Chrome, Firefox, Safari, Edge |

---

## Data Volume

| Entity | Count | Storage |
|--------|-------|---------|
| Cards (oracle-cards) | ~27,000 | ~50-100MB PostgreSQL |
| Deck (localStorage) | 1 per session | ~10KB |
| Sync diff | ~0-50 cards/week | Incremental |

---

## Next Steps After Plan

1. `/speckit.tasks` - Generate detailed task list from this plan
2. `/speckit.taskstoissues` - Create GitHub issues from tasks
3. Begin Increment 1 implementation
