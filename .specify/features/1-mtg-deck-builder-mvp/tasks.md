# Tasks: MTG Deck Builder MVP

**Feature:** 1-mtg-deck-builder-mvp
**Generated:** 2026-01-03
**Spec Version:** 2.3.0
**Plan Version:** 2.0.0

## Overview

This task list implements the MTG Deck Builder MVP with bulk data architecture (no API caching, full local DB).

**User Stories (from spec.md):**
- US1: Card Search - Search for cards by name (text-only display)
- US2: Add Cards to Deck - Add cards from search results
- US3: Manage Deck List - View and modify deck list with persistence
- US4: Select Format - Choose deck format, filter search
- US5: Format Switching - Handle illegal cards on format change
- US6: View Deck Statistics - See deck composition stats

**Architecture:**
- Full Scryfall oracle-cards bulk data (~27k cards) seeded to PostgreSQL
- Text-only card display (no images in MVP)
- Daily/weekly sync for ban list updates

---

## Phase 1: Setup

**Goal:** Phoenix app runs, connects to DB, loads homepage
**Test:** `mix phx.server` starts, http://localhost:4000 loads

- [X] T001 Create Phoenix project with `mix phx.new mtg_deck_builder --live` in project directory
- [X] T002 Configure PostgreSQL database connection in config/dev.exs
- [X] T003 Configure test database in config/test.exs
- [X] T004 [P] Create .env.example with DATABASE_URL in project root
- [X] T005 [P] Add dependencies to mix.exs: tesla ~> 1.7, jason ~> 1.4, credo ~> 1.7, dialyxir ~> 1.4
- [X] T006 Run `mix deps.get` to install dependencies
- [X] T007 Run `mix ecto.create` to create database
- [X] T008 [P] Update lib/mtg_deck_builder_web/components/layouts/root.html.heex with app header/footer
- [X] T009 [P] Create placeholder lib/mtg_deck_builder_web/live/home_live.ex with welcome message
- [X] T010 Update lib/mtg_deck_builder_web/router.ex to route "/" to HomeLive

**Acceptance:** Run `mix phx.server`, visit http://localhost:4000, see welcome page

---

## Phase 2: Foundational - Bulk Data Import & Card Database

**Goal:** Import all ~27k cards from Scryfall bulk data, search works locally
**Test:** `mix cards.import` completes, `Cards.search("bolt")` returns Lightning Bolt
**Dependencies:** Phase 1 complete

- [X] T011 Create migration for cards table in priv/repo/migrations/TIMESTAMP_create_cards.exs with fields: scryfall_id, oracle_id, name, mana_cost, cmc, type_line, oracle_text, colors, color_identity, legalities (map), prices (map), is_basic_land, rarity, set_code
- [X] T012 Add indexes to migration: unique on scryfall_id, btree on name, gin on oracle_text for full-text search
- [X] T013 Run `mix ecto.migrate` to apply migration
- [X] T014 Create lib/mtg_deck_builder/cards/card.ex Ecto schema matching migration fields
- [X] T015 Create lib/mtg_deck_builder/cards/cards.ex context module with module doc
- [X] T016 Create lib/mtg_deck_builder/cards/bulk_importer.ex module
- [X] T017 Implement BulkImporter.get_bulk_data_url/0 to fetch Scryfall bulk-data API and extract oracle-cards download URL
- [X] T018 Implement BulkImporter.download_bulk_file/1 to stream download ~25MB JSON to temp file
- [X] T019 Implement BulkImporter.parse_and_insert/1 to stream-parse JSON and batch insert 1000 cards at a time
- [X] T020 Implement BulkImporter.transform_card/1 to map Scryfall JSON fields to Card schema
- [X] T021 Create lib/mix/tasks/cards.import.ex mix task that calls BulkImporter with progress output
- [X] T022 Implement Cards.search/2 with ILIKE query on name, optional format filter, limit 50 results
- [X] T023 Implement Cards.get_by_scryfall_id/1 for single card lookup
- [X] T024 Implement Cards.count/0 to verify import success
- [ ] T025 [P] Create test/mtg_deck_builder/cards/cards_test.exs with search and lookup tests
- [ ] T026 [P] Create test/mtg_deck_builder/cards/bulk_importer_test.exs with transform_card tests

**Acceptance:**
```bash
mix cards.import
# Output: Downloading oracle-cards.json... Imported 27,XXX cards in X seconds

iex> MtgDeckBuilder.Cards.search("lightning bolt")
[%Card{name: "Lightning Bolt", mana_cost: "{R}", ...}]
```

---

## Phase 3: US1 - Card Search UI (Text-Only)

**Goal:** User can type card name, see text-based results
**Test:** Search "bolt", see Lightning Bolt with name, mana cost, type, oracle text
**Dependencies:** Phase 2 complete

- [X] T027 [US1] Create lib/mtg_deck_builder_web/live/deck_live.ex as main deck editor LiveView
- [X] T028 [US1] Add assigns: search_query, search_results, search_loading, format (default :modern)
- [X] T029 [US1] Create lib/mtg_deck_builder_web/live/deck_live.html.heex with search input and results area
- [X] T030 [US1] Create assets/js/hooks/search_debounce.js with 300ms debounce pushing "search_cards" event
- [X] T031 [US1] Register SearchDebounce hook in assets/js/app.js
- [X] T032 [US1] Implement handle_event("search_cards", %{"query" => query}, socket) in deck_live.ex
- [X] T033 [US1] Create lib/mtg_deck_builder_web/components/card_component.ex for text-only card display
- [X] T034 [US1] Implement card_component to show: name, mana cost (formatted), type line, oracle text (truncated), price
- [ ] T035 [US1] Add expandable card detail on click (shows full oracle text, all legalities)
- [X] T036 [US1] Display "No cards found" message when search returns empty
- [X] T037 [US1] Display loading indicator during search in deck_live.html.heex
- [X] T038 [US1] Update router.ex to route "/" to DeckLive (replace HomeLive)

**Acceptance:** Type "lightning" in search, see Lightning Bolt with "{R} - Instant - Lightning Bolt deals 3 damage to any target."

---

## Phase 4: US2 - Add Cards to Deck

**Goal:** User can add cards from search results to mainboard/sideboard
**Test:** Click "Add to Mainboard" on Lightning Bolt, see it appear in deck list
**Dependencies:** Phase 3 complete

- [X] T039 [US2] Create lib/mtg_deck_builder/decks/deck.ex struct with fields: id, name, format, mainboard, sideboard, removed_cards
- [X] T040 [US2] Create lib/mtg_deck_builder/decks/deck_card.ex struct with fields: scryfall_id, name, quantity, mana_cost, cmc, type_line, colors, price
- [X] T041 [US2] Add deck assign to deck_live.ex mount/3 with empty Deck struct
- [X] T042 [US2] Add "Add to Mainboard" button to card_component.ex search results
- [X] T043 [US2] Add "Add to Sideboard" button to card_component.ex search results
- [X] T044 [US2] Add quantity selector (1-4) dropdown next to add buttons
- [X] T045 [US2] Implement handle_event("add_card", %{"board" => "mainboard", "scryfall_id" => id, "quantity" => qty}, socket)
- [X] T046 [US2] Implement handle_event("add_card", %{"board" => "sideboard", ...}, socket)
- [X] T047 [US2] Create lib/mtg_deck_builder/decks/decks.ex context with add_card/3 function
- [X] T048 [US2] Implement basic 4-copy check in add_card (except basic lands via is_basic_land field)
- [X] T049 [US2] Display error flash when exceeding copy limit
- [X] T050 [US2] Create lib/mtg_deck_builder_web/components/deck_list_component.ex
- [X] T051 [US2] Display mainboard section with card rows in deck_list_component.ex
- [X] T052 [US2] Display sideboard section with card rows in deck_list_component.ex
- [X] T053 [US2] Show card count totals (e.g., "Mainboard: 12 cards") in deck_list_component.ex

**Acceptance:** Add 4 Lightning Bolts to mainboard, see "4x Lightning Bolt {R}" in deck list, 5th copy rejected with error

---

## Phase 5: US3 - Manage Deck List

**Goal:** User can adjust quantities, remove cards, move between boards, persist to localStorage
**Test:** Add cards, refresh page, deck still shows same cards
**Dependencies:** Phase 4 complete

- [X] T054 [US3] Add +/- buttons to each card row in deck_list_component.ex
- [X] T055 [US3] Implement handle_event("update_quantity", %{"scryfall_id" => id, "board" => board, "delta" => 1}, socket)
- [X] T056 [US3] Implement handle_event("update_quantity", %{"delta" => -1, ...}, socket) with auto-remove at 0
- [X] T057 [US3] Add remove button (X icon) to each card row in deck_list_component.ex
- [X] T058 [US3] Implement handle_event("remove_card", %{"scryfall_id" => id, "board" => board}, socket)
- [X] T059 [US3] Add "Move to Sideboard" context option for mainboard cards
- [X] T060 [US3] Add "Move to Mainboard" context option for sideboard cards
- [X] T061 [US3] Implement handle_event("move_card", %{"scryfall_id" => id, "from" => from, "to" => to}, socket)
- [X] T062 [US3] Create assets/js/hooks/deck_storage.js for localStorage sync
- [X] T063 [US3] Implement DeckStorage.mounted() to load deck from localStorage key "mtg_deck"
- [X] T064 [US3] Implement DeckStorage.handleEvent("sync_deck", {deck_json}) to save to localStorage
- [X] T065 [US3] Register DeckStorage hook in assets/js/app.js
- [X] T066 [US3] Implement handle_event("load_deck", %{"deck_json" => json}, socket) to restore deck state
- [X] T067 [US3] Add phx-hook="DeckStorage" to deck container in deck_live.html.heex
- [X] T068 [US3] Push "sync_deck" event after every deck modification in deck_live.ex

**Acceptance:** Add 3 cards, increase one to 4x, move one to sideboard, refresh page - all changes preserved

---

## Phase 6: US4 - Select Format

**Goal:** User can choose format, search results filter to legal cards only
**Test:** Select Standard, search returns only Standard-legal cards
**Dependencies:** Phase 3 complete (can run parallel with US2/US3 after search works)

- [X] T069 [US4] Add format dropdown to deck_live.html.heex header (Standard, Modern, Pioneer, Legacy, Vintage, Pauper)
- [X] T070 [US4] Implement handle_event("change_format", %{"format" => format}, socket)
- [X] T071 [US4] Update Cards.search/2 to filter by legalities map field for selected format
- [X] T072 [US4] Create lib/mtg_deck_builder/decks/validator.ex module
- [X] T073 [US4] Implement Validator.legal_in_format?/2 checking card.legalities[format] == "legal"
- [X] T074 [US4] Filter search results to only legal cards using Validator in deck_live.ex
- [X] T075 [US4] Store format in deck struct and localStorage
- [X] T076 [US4] Load format from localStorage on page mount

**Acceptance:** Switch to Pauper format, search "counterspell", see only common-rarity printings that are Pauper-legal

---

## Phase 7: US5 - Format Switching & Validation

**Goal:** Switching format moves illegal cards to Removed Cards area
**Test:** Build Modern deck with Lightning Bolt, switch to Standard, Bolt moves to Removed Cards
**Dependencies:** Phase 5 and Phase 6 complete

- [X] T077 [US5] Implement Validator.validate_deck/2 returning {:ok, deck} | {:error, errors}
- [X] T078 [US5] Implement Validator.check_copy_limits/1 for 4-copy rule validation
- [X] T079 [US5] Implement Validator.check_restricted/2 for Vintage 1-copy restricted cards
- [X] T080 [US5] Implement Validator.check_sideboard_limit/1 for 15-card max
- [X] T081 [US5] Implement Validator.check_mainboard_minimum/1 for 60-card warning
- [X] T082 [US5] Create lib/mtg_deck_builder/decks/removed_card.ex struct with removal_reason, original_board fields
- [X] T083 [US5] Implement Decks.move_illegal_to_removed/2 that checks legality and moves cards
- [X] T084 [US5] Update change_format handler to call move_illegal_to_removed
- [X] T085 [US5] Display flash notification "X cards moved to Removed Cards (not legal in [format])"
- [X] T086 [US5] Create lib/mtg_deck_builder_web/components/removed_cards_component.ex
- [X] T087 [US5] Display each removed card with removal reason (banned, not_legal, restricted) in component
- [X] T088 [US5] Add "Restore to Mainboard" button to each removed card
- [X] T089 [US5] Add "Restore to Sideboard" button to each removed card
- [X] T090 [US5] Implement handle_event("restore_card", %{"scryfall_id" => id, "board" => board}, socket)
- [X] T091 [US5] Only allow restore if card would be legal in current format (show error otherwise)
- [X] T092 [US5] Display deck validity status banner (Legal ✓ / Illegal ✗) in deck_live.html.heex
- [X] T093 [US5] Display validation errors list when deck is invalid

**Acceptance:**
1. Add Lightning Bolt (Modern legal, Standard not_legal) to deck in Modern format
2. Switch to Standard
3. See notification "1 card moved to Removed Cards"
4. See Lightning Bolt in Removed Cards with reason "not_legal"
5. Switch back to Modern, click "Restore to Mainboard", card returns to mainboard

---

## Phase 8: US6 - Deck Statistics

**Goal:** Real-time stats display (mana curve, colors, types)
**Test:** Add cards, see mana curve bars update immediately
**Dependencies:** Phase 4 complete

- [X] T094 [US6] Create lib/mtg_deck_builder/decks/stats.ex module
- [X] T095 [US6] Implement Stats.calculate/1 taking deck, returning stats map
- [X] T096 [US6] Implement mana_curve/1 returning %{0 => count, 1 => count, ..., "6+" => count}
- [X] T097 [US6] Implement color_distribution/1 returning %{"W" => count, "U" => count, "B" => count, "R" => count, "G" => count, "C" => count}
- [X] T098 [US6] Implement type_breakdown/1 returning %{creature: count, instant: count, sorcery: count, artifact: count, enchantment: count, planeswalker: count, land: count}
- [X] T099 [US6] Implement average_mana_value/1 excluding lands
- [X] T100 [US6] Implement total_price/1 summing all card prices
- [X] T101 [US6] Create lib/mtg_deck_builder_web/components/stats_component.ex
- [X] T102 [US6] Display mana curve as horizontal bars (text-based, e.g., "2: ████ 8")
- [X] T103 [US6] Display color distribution as list with counts
- [X] T104 [US6] Display type breakdown as list with counts
- [X] T105 [US6] Display average mana value
- [X] T106 [US6] Display total deck price
- [X] T107 [US6] Add stats assign to deck_live.ex, recalculate on every deck change
- [X] T108 [US6] Ensure stats recalculation completes in <500ms

**Acceptance:** Add 10 cards of varying costs/colors, see accurate mana curve bars and color counts update instantly

---

## Phase 9: Data Sync & Polish

**Goal:** Sync task for ban updates, error handling, cleanup
**Test:** `mix cards.sync` detects and applies legality changes
**Dependencies:** All previous phases complete

- [ ] T109 Create lib/mtg_deck_builder/cards/bulk_sync.ex module
- [ ] T110 Implement BulkSync.sync/0 that downloads fresh bulk data
- [ ] T111 Implement BulkSync.diff_and_update/1 comparing bulk data to DB, updating changed cards only
- [ ] T112 Implement BulkSync.detect_legality_changes/2 returning list of cards with changed legalities
- [ ] T113 Create lib/mix/tasks/cards.sync.ex mix task with summary output
- [ ] T114 Add comprehensive error handling for bulk download failures in bulk_importer.ex
- [ ] T115 Add retry logic (max 3 attempts) for failed downloads
- [ ] T116 Add loading skeleton UI for search results in deck_live.html.heex
- [ ] T117 Add empty state messaging for deck lists ("No cards yet - search and add some!")
- [ ] T118 Add keyboard shortcut: Enter in search input triggers search
- [ ] T119 Add keyboard shortcut: Escape clears search
- [ ] T120 Verify CSS works in Chrome, Firefox, Safari, Edge
- [X] T121 Update README.md with setup instructions (mix cards.import, etc.)
- [ ] T122 Run `mix credo --strict` and fix all warnings
- [ ] T123 Run `mix dialyzer` and fix all type issues

**Acceptance:**
```bash
mix cards.sync
# Output: Synced 27,XXX cards. 3 cards updated, 1 legality change detected.
```

---

## Dependencies Graph

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational: Bulk Import)
    ↓
Phase 3 (US1: Card Search)
    ↓
    ├── Phase 4 (US2: Add Cards) → Phase 5 (US3: Manage Deck)
    │                                      ↓
    │                              Phase 7 (US5: Format Switching)
    │                                      ↓
    └── Phase 6 (US4: Select Format) ──────┘

Phase 8 (US6: Statistics) ←── depends on Phase 4

Phase 9 (Sync & Polish) ←── depends on all
```

## Parallel Execution Opportunities

**Within Phase 1:**
- T004, T005 (env file, deps) can run parallel
- T008, T009 (layout, home_live) can run parallel

**Within Phase 2:**
- T025, T026 (tests) can run parallel after implementation

**Across Phases:**
- Phase 6 (US4: Format Selection) can start after Phase 3, parallel with Phase 4-5
- Phase 8 (US6: Statistics) can start after Phase 4, parallel with Phase 5-7

## Implementation Strategy

1. **MVP Scope:** Phases 1-4 (Setup + Bulk Import + Search + Add Cards) = core functionality
2. **First Milestone:** Run `mix cards.import`, search cards, add to deck
3. **Incremental Delivery:** Each phase is independently testable
4. **Risk Mitigation:** Bulk import (Phase 2) is highest risk - test thoroughly

---

## Summary

| Metric | Value |
|--------|-------|
| **Total Tasks** | 123 |
| **Setup Tasks** | 10 |
| **Foundational Tasks (Bulk Import)** | 16 |
| **US1 (Card Search)** | 12 |
| **US2 (Add Cards)** | 15 |
| **US3 (Manage Deck)** | 15 |
| **US4 (Select Format)** | 8 |
| **US5 (Format Switching)** | 17 |
| **US6 (Statistics)** | 15 |
| **Sync & Polish Tasks** | 15 |
| **Parallel Opportunities** | 10+ tasks marked [P] |

**Suggested First Milestone:** Complete Phases 1-4 (53 tasks) for basic deck building functionality.
