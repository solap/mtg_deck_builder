# Feature Specification: MTG Deck Builder MVP

**Version:** 2.3.0
**Created:** 2026-01-03
**Status:** Draft

## Overview

A Magic: The Gathering deck builder with a visual interface for searching cards and managing deck lists. MVP is UI-only with no AI features - users interact through traditional search and click interfaces.

**Vision:** "Claude Code for Magic decks" - groundbreaking AI assistance that understands deck strategy at a deep level (coming in later phases).

MVP focuses on 60-card constructed formats with basic deck management via UI only.

## Clarifications

### Session 2026-01-03
- Q: Which formats to support in MVP? → A: 60-card formats only (Standard, Modern, Pioneer, Legacy, Vintage, Pauper) - Commander deferred to later phase
- Q: Deck structure? → A: Mainboard (60 cards) + Sideboard (15 cards) as separate lists
- Q: Card legality handling? → A: Only allow format-legal cards to be added
- Q: Format switch with illegal cards? → A: Auto-remove illegal cards to a "removed cards" holding area
- Q: MVP scope? → A: UI-only basic deck management. No AI in MVP.
- Q: Phase 1 scope? → A: AI chat for basic commands (add/delete/update/move)
- Q: Phase 2 scope? → A: AI Semantic Search - translate natural language intent to Scryfall search facets (reuses Phase 1 command infrastructure)
- Q: Phase 2 architecture? → A: Semantic keyword mappings. AI expands user intent using curated MTG terminology → Scryfall syntax queries. No embeddings needed - MTG vocabulary is well-defined. Poll Scryfall bulk data weekly for new sets/cards.
- Q: Secondary data sources? → A: Design for multi-source from start. Scryfall = primary (card data, search). Consider EDHREC (synergy), MTGGoldfish (meta), TCGPlayer (pricing) for enrichment.
- Q: Phase 3 scope? → A: AI for deck improvement with multi-agent analysis
- Q: Restricted cards handling? → A: Enforce restriction (max 1 copy for restricted cards in Vintage)
- Q: Canadian Highlander format? → A: 100-card singleton format (like Commander), moved to Phase 8 with other 100-card formats
- Q: How to handle ban list updates? → A: Seed full Scryfall oracle-cards bulk data (~27k cards) locally in PostgreSQL. Daily/weekly sync to detect legality changes and new cards.
- Q: Which Scryfall bulk data? → A: Oracle cards only (~27k). No alternate printings/art variants.
- Q: Card images in MVP? → A: No images - text-only display (name, mana cost, type, oracle text, price). Art deferred to later phase.
- Q: Embeddings vs semantic mappings for search? → A: Semantic keyword mappings only. Curated MTG terminology → Scryfall syntax expansion. No embeddings - MTG vocabulary is well-defined.

## Problem Statement

Building competitive MTG decks requires deep knowledge of card interactions, format rules, mana curves, and meta-game awareness. New and casual players struggle to build viable decks, while experienced players spend significant time manually optimizing deck compositions. Existing deck builders provide card databases but lack intelligent assistance for strategic deck construction.

## Target Users

### Primary Users
- **Casual MTG Players**: Want help building fun, functional decks without extensive meta knowledge
- **Returning Players**: Familiar with MTG basics but need guidance on current card pools and strategies
- **Budget-Conscious Players**: Need to build competitive decks within price constraints

### Secondary Users
- **Experienced Players**: Want AI-powered analysis to optimize existing decks
- **Deck Brewers**: Enjoy experimenting and want suggestions for unconventional synergies

## Product Roadmap

| Phase | Name | Key Features | Notes |
|-------|------|--------------|-------|
| **MVP** | Basic Deck Builder | 60-card formats, card search by name, single deck UI management, format validation, deck statistics | This spec - NO AI |
| **Phase 1** | AI Chat Commands | AI-powered chat for basic deck operations (add/delete/update/move cards via natural language) | First AI integration, builds command parsing infrastructure |
| **Phase 2** | AI Semantic Search | Natural language card search ("find red 2-mana protection for creatures"), curated MTG terminology mappings, AI expands intent → Scryfall syntax queries, new set detection & cache updates | Reuses Phase 1 intent parsing, no embeddings needed |
| **Phase 3** | Multi-Agent AI | Mana base agent, win condition agent, synergy agent, deck improvement suggestions, parallel analysis | THE BIG DEAL - "Claude Code for Magic" |
| **Phase 4** | Multiple Decks | Create/select/delete multiple decks, deck list view, copy/duplicate | Deck management |
| **Phase 5** | Import/Export | Paste deck lists, export to text, standard formats | Bring existing decks |
| **Phase 6** | More 60-Card Formats | Oathbreaker, other 60-card variants | Niche but passionate |
| **Phase 7** | Meta & Combos | Meta tracking, combo detection, matchup analysis | Advanced AI |
| **Phase 8** | 100-Card Formats | Commander, Canadian Highlander - 100-card singleton, color identity rules | Different rules engine |
| **Phase 9** | User Accounts | Authentication, saved decks, sharing, social features | Community features |
| **Phase 10** | Budget Tools | Price optimization, budget alternatives, price alerts | Cost-conscious features |
| **Phase 11** | Card Images | Card artwork display, alternate art selection, high-res images | Visual polish |

## User Scenarios & Testing

### Scenario 1: Card Search
**As a** deck builder
**I want to** search for cards by name
**So that** I can find cards to add to my deck

**Acceptance Criteria:**
- User can type card name in search box
- Search supports fuzzy/partial matching (typos, partial names)
- Results are ranked by match quality (closest matches first)
- Each result shows: name, mana cost, type, oracle text, price (text-only, no images)
- User can click a result to see full card details

### Scenario 2: Add Cards to Deck
**As a** deck builder
**I want to** add cards from search results to my deck
**So that** I can build my deck composition

**Acceptance Criteria:**
- User can click "Add to Mainboard" or "Add to Sideboard" on a search result
- User can specify quantity when adding (default: 1)
- System enforces 4-copy maximum (except basic lands), 1-copy for Vintage restricted cards
- System rejects cards not legal in selected format with clear error
- Added cards appear in deck list immediately

### Scenario 3: Manage Deck List
**As a** deck builder
**I want to** view and modify my deck list
**So that** I can adjust my deck composition

**Acceptance Criteria:**
- User can view all cards in mainboard and sideboard separately
- Each card shows: name, quantity, mana cost, type, price
- User can increase/decrease card quantity with +/- buttons
- User can remove cards entirely
- User can move cards between mainboard and sideboard
- Changes persist across browser sessions

### Scenario 4: Select Format
**As a** tournament player
**I want to** choose my deck's format
**So that** the system validates my deck correctly

**Acceptance Criteria:**
- User can select format: Standard, Modern, Pioneer, Legacy, Vintage, Pauper
- Format selection filters search results to legal cards only
- System validates existing cards against new format on switch
- Deck validity status is clearly displayed (legal/illegal with reasons)

### Scenario 5: Format Switching
**As a** deck builder
**I want to** change my deck's format and handle newly illegal cards gracefully
**So that** I can adapt my deck to different tournaments

**Acceptance Criteria:**
- User can change format at any time
- Newly illegal cards are automatically moved to a "Removed Cards" holding area
- System shows notification: "X cards moved to Removed Cards (not legal in [format])"
- User can view removed cards and see why each was removed
- User can restore cards if they switch back to a permissive format
- Removed cards area is separate from mainboard/sideboard

### Scenario 6: View Deck Statistics
**As a** deck builder
**I want to** see statistics about my deck composition
**So that** I can identify balance issues

**Acceptance Criteria:**
- User can view mana curve distribution (visual chart)
- User can view color distribution (pie chart or breakdown)
- User can view card type breakdown (creatures, spells, lands)
- User can view average mana value
- Statistics update in real-time as deck changes

## Functional Requirements

### FR1: Card Search & Display
- FR1.1: System SHALL provide a search input for card names
- FR1.2: System SHALL search cards by name with fuzzy matching (close matches ranked by similarity)
- FR1.3: System SHALL filter search results by selected format legality
- FR1.4: System SHALL display card data as text (no images in MVP - art deferred to later phase)
- FR1.5: System SHALL show card details: name, mana cost, type, oracle text, legalities, prices
- FR1.6: System SHALL seed complete Scryfall oracle-cards bulk data (~27k cards) into local PostgreSQL
- FR1.7: System SHALL sync bulk data daily/weekly to detect ban list changes and new cards

### FR2: Deck List Management (UI)
- FR2.1: System SHALL maintain three lists: mainboard, sideboard, and removed cards
- FR2.2: System SHALL provide "Add to Mainboard" and "Add to Sideboard" buttons on search results
- FR2.3: System SHALL allow specifying quantity when adding cards
- FR2.4: System SHALL allow updating card quantity via +/- buttons
- FR2.5: System SHALL allow deleting cards from any list
- FR2.6: System SHALL allow moving cards between mainboard and sideboard via UI
- FR2.7: System SHALL display cards with key stats: name, quantity, mana cost, type, price
- FR2.8: System SHALL persist deck data across browser sessions
- FR2.9: System SHALL reject adding cards not legal in the selected format

### FR3: Format Validation & Switching
- FR3.1: System SHALL provide format selector: Standard, Modern, Pioneer, Legacy, Vintage, Pauper
- FR3.2: System SHALL validate card legality per selected format before adding
- FR3.3: System SHALL enforce 4-copy maximum per card (except basic lands), and 1-copy maximum for restricted cards in Vintage
- FR3.4: System SHALL enforce mainboard minimum of 60 cards for validation
- FR3.5: System SHALL enforce sideboard maximum of 15 cards
- FR3.6: System SHALL display validation errors with clear explanations
- FR3.7: System SHALL indicate deck validity status (legal/illegal with reasons)
- FR3.8: System SHALL auto-move illegal cards to "Removed Cards" on format switch
- FR3.9: System SHALL display reason for each removed card (banned, not in format, restricted)
- FR3.10: System SHALL allow restoring removed cards when switching to permissive format

### FR4: Deck Statistics (Local)
- FR4.1: System SHALL calculate and display mana curve distribution
- FR4.2: System SHALL calculate and display color distribution
- FR4.3: System SHALL calculate and display card type breakdown
- FR4.4: System SHALL calculate average mana value
- FR4.5: System SHALL update statistics in real-time (<500ms) on deck changes

## Edge Cases & Error Handling

### Format Switching
- When switching to a more restrictive format, illegal cards move to Removed Cards with explanation
- When switching to a more permissive format, user is notified they can restore removed cards
- If all cards become illegal, deck shows empty with prominent restore option

### Card Search
- No results: Show "No cards found" with search suggestions
- API failure: Show cached results if available, otherwise error with retry option
- Rate limited: Queue requests, show loading indicator

### Deck Validation
- Under 60 cards: Warning state, not error (deck in progress)
- Over 15 sideboard: Error, prevent adding more
- 5th copy of non-basic: Error with explanation
- 2nd copy of restricted card (Vintage): Error with explanation that card is restricted to 1 copy

## Non-Functional Requirements

### Performance
- Card search results SHALL appear within 2 seconds
- Deck statistics SHALL update within 500ms of changes
- System SHALL support at least 100 concurrent users

### Reliability
- System SHALL gracefully handle external API failures with cached fallbacks
- System SHALL not lose deck data during browser refresh

### Usability
- Interface SHALL work on desktop browsers (Chrome, Firefox, Safari, Edge)
- Card images SHALL be clearly visible at default zoom
- Error messages SHALL explain what went wrong and suggest fixes

## Assumptions

- Scryfall API will remain freely available for card data
- Users have stable internet connections
- Card prices from external sources are approximate and may fluctuate
- Users are familiar with basic MTG terminology (mana, colors, formats)

## Out of Scope (This Phase)

See Product Roadmap for future phases. The following are explicitly NOT in MVP:

- **Any AI features** (Phase 1+)
- Chat interface for deck commands (Phase 1)
- AI semantic search / natural language card finding (Phase 2)
- AI deck improvement suggestions (Phase 3)
- Multiple decks (Phase 4)
- Import/export deck lists (Phase 5)
- Oathbreaker format (Phase 6)
- Meta tracking, combo detection (Phase 7)
- Commander, Canadian Highlander (Phase 8 - 100-card formats)
- User authentication and accounts (Phase 9)
- Budget optimization (Phase 10)
- Card images/artwork (Phase 11)
- Mobile-native applications (responsive web only)
- Multiple language support
- Drag-and-drop reordering

## Dependencies

- Scryfall bulk data (oracle-cards) for initial seed and periodic sync
- PostgreSQL for complete card database (~27k cards)
- Database for deck storage (localStorage in MVP, PostgreSQL in later phases)

## Success Criteria

1. **Deck Building Efficiency**: Users can create a complete, format-legal 60-card deck in under 15 minutes using UI
2. **Search Effectiveness**: Users find desired cards within 3 search attempts 90% of the time
3. **Session Reliability**: No deck data loss during normal usage across browser sessions
4. **Format Compliance**: System correctly validates format legality 100% of the time
5. **Format Switch UX**: Users successfully navigate format changes without losing desired cards
6. **User Satisfaction**: Users rate deck building experience 4+ out of 5 stars
