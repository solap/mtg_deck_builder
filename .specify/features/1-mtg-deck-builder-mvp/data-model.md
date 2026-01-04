# Data Model: MTG Deck Builder MVP

**Feature:** 1-mtg-deck-builder-mvp
**Date:** 2026-01-03

## Entities

### 1. CachedCard

Cached card data from Scryfall API to reduce external calls.

```elixir
schema "cached_cards" do
  field :scryfall_id, :string        # Primary identifier from Scryfall
  field :name, :string               # Card name (searchable)
  field :mana_cost, :string          # e.g., "{2}{U}{U}"
  field :cmc, :float                 # Converted mana cost / mana value
  field :type_line, :string          # e.g., "Creature — Human Wizard"
  field :oracle_text, :string        # Rules text
  field :colors, {:array, :string}   # ["U", "W"] etc.
  field :color_identity, {:array, :string}  # For future Commander support
  field :legalities, :map            # %{"standard" => "legal", "modern" => "banned", ...}
  field :prices, :map                # %{"usd" => "1.23", "usd_foil" => "4.56"}
  field :image_uris, :map            # %{"small" => "url", "normal" => "url", ...}
  field :card_faces, {:array, :map}  # For DFCs, split cards, etc.
  field :is_basic_land, :boolean     # Precomputed for 4-copy rule

  timestamps()  # inserted_at used for cache TTL
end

# Indexes
create index(:cached_cards, [:scryfall_id], unique: true)
create index(:cached_cards, [:name])
create index(:cached_cards, [:inserted_at])
```

**Validation Rules:**
- `scryfall_id` is required and unique
- `name` is required
- Cache expires after 24 hours (check `inserted_at`)

**State Transitions:** None (immutable cache entry, replaced on refresh)

---

### 2. Deck (Client-Side Only - MVP)

Stored in browser localStorage as JSON. No server persistence in MVP.

```typescript
interface Deck {
  id: string;                    // UUID generated client-side
  name: string;                  // User-provided deck name
  format: Format;                // Selected format
  mainboard: DeckCard[];         // 60+ cards
  sideboard: DeckCard[];         // 0-15 cards
  removedCards: RemovedCard[];   // Cards moved due to format switch
  createdAt: string;             // ISO timestamp
  updatedAt: string;             // ISO timestamp
}

interface DeckCard {
  scryfallId: string;            // Reference to card
  name: string;                  // Denormalized for display
  quantity: number;              // 1-4 (or unlimited for basic lands)
  manaCost: string;              // Denormalized for stats
  cmc: number;                   // Denormalized for stats
  typeLine: string;              // Denormalized for categorization
  colors: string[];              // Denormalized for stats
  imageUri: string;              // Denormalized (small image)
  priceUsd: string | null;       // Denormalized for display
}

interface RemovedCard extends DeckCard {
  removalReason: string;         // "banned", "not_legal", "restricted"
  removedFromBoard: "mainboard" | "sideboard";
}

type Format = "standard" | "modern" | "pioneer" | "legacy" | "vintage" | "pauper";
```

**Validation Rules:**
- `mainboard` minimum 60 cards (warning if less, not error)
- `sideboard` maximum 15 cards (error if exceeded)
- Non-basic cards maximum 4 copies across mainboard + sideboard
- Basic lands unlimited copies
- All cards must be `legal` in selected format (else moved to `removedCards`)

**State Transitions:**
```
[Empty Deck] --add cards--> [Building]
[Building] --60+ cards--> [Valid]
[Valid] --change format--> [Building] (illegal cards moved)
[Building] --restore cards--> [Building/Valid]
```

---

### 3. SearchResult (Ephemeral)

Transient data structure for search results, not persisted.

```elixir
defmodule MtgDeckBuilder.Cards.SearchResult do
  defstruct [
    :scryfall_id,
    :name,
    :mana_cost,
    :cmc,
    :type_line,
    :oracle_text,
    :colors,
    :legalities,
    :prices,
    :image_uris,
    :is_basic_land,
    :is_legal_in_format  # Computed based on current deck format
  ]
end
```

---

### 4. DeckStats (Computed)

Calculated on-the-fly from deck contents, not persisted.

```typescript
interface DeckStats {
  totalCards: number;            // mainboard count
  manaCurve: ManaCurveData;      // Distribution by CMC
  colorDistribution: ColorData;  // Count by color
  typeBreakdown: TypeData;       // Count by card type
  averageManaValue: number;      // Avg CMC (excluding lands)
  isValid: boolean;              // Meets format requirements
  validationErrors: string[];    // List of issues
}

interface ManaCurveData {
  [cmc: number]: number;         // CMC -> count (6+ grouped as "6")
}

interface ColorData {
  W: number;  // White
  U: number;  // Blue
  B: number;  // Black
  R: number;  // Red
  G: number;  // Green
  C: number;  // Colorless
}

interface TypeData {
  creature: number;
  instant: number;
  sorcery: number;
  artifact: number;
  enchantment: number;
  planeswalker: number;
  land: number;
  other: number;
}
```

---

## Entity Relationships

```
┌─────────────────┐
│   CachedCard    │ (PostgreSQL - server cache)
│   scryfall_id   │
└────────┬────────┘
         │
         │ referenced by
         ▼
┌─────────────────┐
│     Deck        │ (localStorage - client)
│  mainboard[]    │──────┐
│  sideboard[]    │──────┤
│  removedCards[] │──────┤
└─────────────────┘      │
                         │
                         ▼
                  ┌─────────────────┐
                  │    DeckCard     │ (embedded in Deck)
                  │   scryfallId    │ ─── references CachedCard
                  │   (denormalized │
                  │    card data)   │
                  └─────────────────┘
```

---

## Data Volume Assumptions

| Entity | Expected Volume | Storage |
|--------|-----------------|---------|
| CachedCard | ~25,000 unique cards | PostgreSQL (~50MB) |
| Deck | 1 per user session | localStorage (~10KB) |
| SearchResult | ~50 per search | Memory only |

---

## Migration Plan

### Migration 001: Create cached_cards table

```elixir
def change do
  create table(:cached_cards, primary_key: false) do
    add :id, :binary_id, primary_key: true
    add :scryfall_id, :string, null: false
    add :name, :string, null: false
    add :mana_cost, :string
    add :cmc, :float
    add :type_line, :string
    add :oracle_text, :text
    add :colors, {:array, :string}, default: []
    add :color_identity, {:array, :string}, default: []
    add :legalities, :map, default: %{}
    add :prices, :map, default: %{}
    add :image_uris, :map, default: %{}
    add :card_faces, {:array, :map}, default: []
    add :is_basic_land, :boolean, default: false

    timestamps()
  end

  create unique_index(:cached_cards, [:scryfall_id])
  create index(:cached_cards, [:name])
  create index(:cached_cards, [:inserted_at])
end
```
