# Research: MTG Deck Builder MVP

**Feature:** 1-mtg-deck-builder-mvp
**Date:** 2026-01-03

## Technical Context Resolution

### 1. Card Data API: Scryfall

**Decision:** Use Scryfall API for all card data

**Rationale:**
- Free, no API key required
- Comprehensive MTG data (25,000+ cards)
- Includes legalities per format, prices, images
- Well-documented REST API
- Rate limit: 10 requests/second (100ms minimum between requests)

**Alternatives Considered:**
- MTG JSON (bulk data only, no search API)
- Gatherer (Wizards official, but no API)
- TCGPlayer API (requires partnership, focused on pricing)

**Key Endpoints:**
- `GET /cards/search?q={query}` - Fuzzy search by name
- `GET /cards/named?fuzzy={name}` - Single card fuzzy match
- `GET /cards/{id}` - Get card by Scryfall ID

**Caching Strategy:**
- Cache card data in PostgreSQL with 24-hour TTL
- Cache search results for 1 hour
- Images: hotlink from Scryfall CDN (no local storage needed)

---

### 2. Frontend Framework: Phoenix LiveView

**Decision:** Phoenix LiveView for real-time UI

**Rationale:**
- Constitution Principle 3 (Boring Technology): Standard Phoenix pattern
- Real-time updates without custom WebSocket code
- Server-side rendering with client-side feel
- No separate frontend build process
- Built-in form handling and validation

**Alternatives Considered:**
- React/Next.js (adds complexity, separate deployment)
- Vue.js with Phoenix API (two codebases)
- Vanilla Phoenix templates (no real-time updates)

**Key Patterns:**
- LiveView for deck editor (real-time stats updates)
- LiveComponents for reusable card display
- Streams for efficient list rendering
- PubSub for potential future multi-user features

---

### 3. Session Storage: Browser localStorage + Server Session

**Decision:** Hybrid storage approach

**Rationale:**
- Constitution Principle 4: Anonymous/session-based acceptable for MVP
- No user accounts in MVP = no server-side user storage
- localStorage for deck persistence across sessions
- Server session for temporary state during editing

**Implementation:**
- Deck stored as JSON in localStorage keyed by deck ID
- Server session holds active deck for LiveView state
- On page load: hydrate LiveView state from localStorage
- On change: sync to localStorage immediately

**Alternatives Considered:**
- Server-only PostgreSQL (requires auth, overkill for MVP)
- IndexedDB (more complex, similar benefits to localStorage)
- Cookies (size limits, sent with every request)

---

### 4. Fuzzy Search: Scryfall + Client-Side Filtering

**Decision:** Rely on Scryfall's fuzzy search + local format filtering

**Rationale:**
- Scryfall already implements excellent fuzzy matching
- Filter results client-side by format legality
- Avoids duplicating search logic

**Implementation:**
- User types → debounce 300ms → call Scryfall
- Filter response by `card.legalities[format] == "legal"`
- Display filtered results ranked by Scryfall's relevance

---

### 5. Format Legality Data Source

**Decision:** Use Scryfall's legalities field

**Rationale:**
- Scryfall maintains up-to-date ban lists
- Each card includes `legalities` map: `{standard: "legal", modern: "banned", ...}`
- No need to maintain our own ban list

**Format Mapping:**
| Our Format | Scryfall Key |
|------------|--------------|
| Standard   | `standard`   |
| Modern     | `modern`     |
| Pioneer    | `pioneer`    |
| Legacy     | `legacy`     |
| Vintage    | `vintage`    |
| Pauper     | `pauper`     |

**Legality Values:**
- `legal` - Can include in deck
- `not_legal` - Not printed in format's sets
- `banned` - Explicitly banned
- `restricted` - Limited to 1 copy (Vintage only)

---

### 6. Deck Statistics Calculation

**Decision:** Client-side calculation in LiveView

**Rationale:**
- All data already in memory (deck list + card details)
- Real-time updates (<500ms requirement)
- No server round-trip needed

**Calculations:**
- **Mana Curve:** Group cards by CMC (0, 1, 2, 3, 4, 5, 6+), count quantities
- **Color Distribution:** Parse mana_cost string, count color symbols
- **Type Breakdown:** Parse type_line, categorize (Creature, Instant, Sorcery, Artifact, Enchantment, Planeswalker, Land)
- **Average MV:** Sum(CMC × quantity) / Sum(quantity), excluding lands

---

### 7. Card Image Handling

**Decision:** Hotlink Scryfall CDN images

**Rationale:**
- Scryfall explicitly allows hotlinking
- Fast CDN, no storage costs
- Multiple image sizes available
- Respects their terms of service

**Image URIs from API:**
```json
"image_uris": {
  "small": "https://cards.scryfall.io/small/...",
  "normal": "https://cards.scryfall.io/normal/...",
  "large": "https://cards.scryfall.io/large/...",
  "art_crop": "https://cards.scryfall.io/art_crop/..."
}
```

**Usage:**
- Search results: `small` (146×204)
- Deck list: `small`
- Card detail modal: `normal` (488×680)

---

## Constitution Compliance Check

| Principle | Compliance | Notes |
|-----------|------------|-------|
| Incremental Delivery | ✅ | Plan breaks into testable increments |
| AI-Native Architecture | ✅ N/A | MVP has no AI features |
| Boring Technology | ✅ | Phoenix LiveView, PostgreSQL, standard patterns |
| Working Code Over Perfect | ✅ | Session storage acceptable, no auth needed |

---

## Open Questions Resolved

1. **Q: How to handle double-faced cards?**
   A: Scryfall returns both faces in `card_faces` array. Display front face by default, show flip on hover/click.

2. **Q: What about split cards, adventures, MDFCs?**
   A: Same approach - Scryfall normalizes all these. Use `card_faces[0]` for primary display.

3. **Q: Rate limiting strategy?**
   A: Debounce search input (300ms), respect 100ms minimum between API calls, queue requests if needed.

4. **Q: Basic land identification?**
   A: Check `type_line` contains "Basic Land" for unlimited copies rule.
