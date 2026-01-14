# Feature Specification: AI Chat Commands

**Version:** 1.0.0
**Created:** 2026-01-04
**Status:** Draft

## Overview

Add an AI-powered chat interface to the MTG Deck Builder that allows users to manage their deck through natural language commands. Users can add, remove, update quantities, and move cards between mainboard/sideboard by typing commands like "add 4 lightning bolt" or "move 2 counterspell to sideboard" instead of clicking through the UI.

This is the first AI integration for the deck builder, establishing the command parsing infrastructure that will be reused in Phase 2 (AI Semantic Search) and Phase 3 (Multi-Agent Analysis).

## Clarifications

### Session 2026-01-04
- Q: How should the system handle AI API failures? → A: Show error and suggest UI - display "AI temporarily unavailable, please use UI controls"
- Q: How should the system manage API costs? → A: No limits; add admin screen showing costs broken down by AI provider (admin auth deferred to later phase)
- Q: Which AI provider should be primary for command parsing? → A: Anthropic Claude

## Problem Statement

While the MVP provides a functional click-based interface for deck building, experienced players often find it faster to type commands than to search, scroll, and click. Additionally, this phase establishes the foundational AI architecture that enables the "Claude Code for Magic" vision where users can interact with their deck through natural conversation.

## Target Users

### Primary Users
- **Power Users**: Want faster deck editing through keyboard commands
- **Experienced Players**: Familiar with card names, prefer typing over clicking
- **Streamers/Content Creators**: Want to demonstrate deck changes quickly on stream

### Secondary Users
- **All MVP Users**: Can continue using click-based UI alongside chat commands
- **Mobile Users**: May find typing commands easier than precise tapping

## User Scenarios & Testing

### Scenario 1: Add Cards via Chat
**As a** deck builder
**I want to** type a command to add cards
**So that** I can quickly add cards without searching and clicking

**Acceptance Criteria:**
- User can type "add 4 lightning bolt" in chat input
- System recognizes card name with fuzzy matching
- System adds specified quantity to mainboard by default
- User can specify board: "add 2 counterspell to sideboard"
- System confirms action: "Added 4x Lightning Bolt to mainboard"
- If card not found, system suggests closest matches
- If quantity exceeds limit, system shows error with current count

### Scenario 2: Remove Cards via Chat
**As a** deck builder
**I want to** type a command to remove cards
**So that** I can quickly adjust my deck composition

**Acceptance Criteria:**
- User can type "remove lightning bolt" to remove all copies
- User can type "remove 2 lightning bolt" to remove specific quantity
- System confirms: "Removed 2x Lightning Bolt from mainboard"
- If card not in deck, system shows "Lightning Bolt is not in your deck"
- User can specify board: "remove counterspell from sideboard"

### Scenario 3: Update Card Quantity via Chat
**As a** deck builder
**I want to** type a command to change card quantities
**So that** I can fine-tune my deck quickly

**Acceptance Criteria:**
- User can type "set lightning bolt to 3" to change quantity
- User can type "add 1 more lightning bolt" for incremental changes
- System enforces 4-copy maximum (except basic lands)
- System confirms: "Updated Lightning Bolt to 3 copies"
- Works for both mainboard and sideboard with board specification

### Scenario 4: Move Cards Between Boards via Chat
**As a** deck builder
**I want to** type a command to move cards between mainboard and sideboard
**So that** I can reorganize my deck quickly

**Acceptance Criteria:**
- User can type "move 2 lightning bolt to sideboard"
- User can type "move counterspell to mainboard"
- If no quantity specified, moves all copies
- System confirms: "Moved 2x Lightning Bolt to sideboard"
- If card not in source board, system shows helpful error

### Scenario 5: View Deck Status via Chat
**As a** deck builder
**I want to** ask about my deck's current state
**So that** I can make informed decisions

**Acceptance Criteria:**
- User can type "how many lightning bolt" to see count
- User can type "show mainboard" to list mainboard cards
- User can type "deck status" to see card counts and validity
- Responses are concise and formatted for readability

### Scenario 6: Undo Last Action via Chat
**As a** deck builder
**I want to** undo my last chat command
**So that** I can quickly fix mistakes

**Acceptance Criteria:**
- User can type "undo" to reverse last chat action
- System confirms what was undone: "Undone: Added 4x Lightning Bolt"
- Only undoes chat-initiated actions (not UI clicks)
- Single level of undo (last action only)

### Scenario 7: View API Costs (Admin)
**As an** administrator
**I want to** view API usage costs broken down by provider
**So that** I can monitor and manage expenses

**Acceptance Criteria:**
- Admin can access a cost dashboard at /admin/costs (no auth required initially)
- Dashboard shows total API costs for configurable time period
- Costs are broken down by provider (Anthropic, OpenAI, xAI)
- Dashboard shows request count and token usage per provider
- Data updates in near real-time as API calls are made

## Functional Requirements

### FR1: Chat Interface
- FR1.1: System SHALL provide a text input field for chat commands
- FR1.2: System SHALL display chat history showing commands and responses
- FR1.3: System SHALL process commands on Enter key press
- FR1.4: System SHALL support command history navigation with up/down arrows
- FR1.5: System SHALL provide visual feedback while processing commands

### FR2: Command Parsing
- FR2.1: System SHALL recognize add commands: "add [quantity] [card name] [to board]"
- FR2.2: System SHALL recognize remove commands: "remove [quantity] [card name] [from board]"
- FR2.3: System SHALL recognize update commands: "set [card name] to [quantity]"
- FR2.4: System SHALL recognize move commands: "move [quantity] [card name] to [board]"
- FR2.5: System SHALL recognize query commands: "how many [card name]", "show [board]", "deck status"
- FR2.6: System SHALL recognize undo command: "undo"
- FR2.7: System SHALL handle optional parameters with sensible defaults (quantity=1, board=mainboard)
- FR2.8: System SHALL support common variations and synonyms (e.g., "delete" = "remove", "mb" = "mainboard")

### FR3: Card Name Resolution
- FR3.1: System SHALL match card names using fuzzy matching (handle typos, partial names)
- FR3.2: System SHALL resolve ambiguous names by presenting options to user
- FR3.3: System SHALL remember recent card selections to speed up repeat commands
- FR3.4: System SHALL only match cards legal in the current format

### FR4: Command Execution
- FR4.1: System SHALL validate commands against deck rules before execution
- FR4.2: System SHALL enforce 4-copy maximum (except basic lands)
- FR4.3: System SHALL enforce format legality for added cards
- FR4.4: System SHALL enforce sideboard 15-card maximum
- FR4.5: System SHALL update deck state and sync to localStorage after each command
- FR4.6: System SHALL update UI to reflect changes immediately

### FR5: Response Messages
- FR5.1: System SHALL confirm successful actions with specific details
- FR5.2: System SHALL explain errors clearly with suggested fixes
- FR5.3: System SHALL suggest card names when no exact match found
- FR5.4: System SHALL format responses for easy reading (card counts, lists)

### FR6: Undo Functionality
- FR6.1: System SHALL track the last chat-initiated action
- FR6.2: System SHALL reverse the last action on "undo" command
- FR6.3: System SHALL confirm what was undone
- FR6.4: System SHALL clear undo state after successful undo (no redo)

### FR7: API Cost Tracking
- FR7.1: System SHALL log all AI API calls with provider, token count, and estimated cost
- FR7.2: System SHALL provide an admin screen displaying API usage costs
- FR7.3: System SHALL break down costs by AI provider (Anthropic, OpenAI, xAI)
- FR7.4: System SHALL NOT impose rate limits on API usage
- FR7.5: Admin authentication/authorization is deferred to a later phase (screen accessible without auth initially)

## Edge Cases & Error Handling

### Ambiguous Card Names
- Multiple matches: Present numbered list, user types number to select
- No matches: Suggest closest matches, ask user to try again
- Partial match: If single close match with >80% similarity, ask for confirmation

### Invalid Commands
- Unrecognized command: Show help text with example commands
- Missing card name: Prompt user to specify card
- Invalid quantity: Show valid range (1-4 for non-basics, 1-15 for sideboard total)

### Deck State Conflicts
- Adding card already at max copies: Show current count, suggest alternative
- Removing card not in deck: Show what cards are in deck
- Moving from empty board: Show which board has the card

### Format Restrictions
- Adding illegal card: Show why card is illegal (banned, not in format)
- Adding restricted card at 2+ copies (Vintage): Enforce 1-copy maximum

### API Failures
- AI API unavailable (network, rate limit, outage): Display "AI temporarily unavailable, please use UI controls"
- User can continue using click-based UI while chat is degraded
- No local fallback parsing - chat requires API connectivity

## Non-Functional Requirements

### Performance
- Command parsing SHALL complete within 200ms
- Card name matching SHALL return results within 500ms
- UI updates SHALL reflect changes within 100ms of command completion

### Usability
- Chat input SHALL be accessible via keyboard shortcut (/)
- Command syntax SHALL be intuitive for English speakers
- Error messages SHALL be friendly and actionable
- Help command SHALL show all available commands with examples

### Reliability
- Failed commands SHALL NOT corrupt deck state
- Chat history SHALL persist across page refreshes (with deck data)
- Network failures SHALL NOT affect local command execution

## Assumptions

- Users have basic familiarity with MTG card names
- Users prefer typing over clicking for repetitive tasks
- English is the primary language for commands (localization deferred)
- AI/LLM integration handles natural language parsing (not regex-based)
- Anthropic Claude API is available for command parsing

## Out of Scope (This Phase)

- **Semantic card search** (Phase 2) - e.g., "find red removal spells"
- **Deck improvement suggestions** (Phase 3) - e.g., "suggest cards for my mana base"
- **Multi-turn conversations** - each command is independent
- **Voice input** - text only
- **Batch commands** - one action per message
- **Custom command aliases** - fixed command vocabulary
- **Command macros or scripting**

## Dependencies

- MVP deck builder functionality (complete)
- Card database with search capability (complete)
- Anthropic Claude API for natural language command parsing (primary provider)
- localStorage for chat history persistence
- PostgreSQL for API usage/cost logging

## Success Criteria

1. **Command Efficiency**: Users can add/remove/update cards via chat faster than via UI (measured by action completion time)
2. **Recognition Accuracy**: 95% of well-formed commands are parsed correctly on first attempt
3. **Card Matching**: Users find the correct card within 2 command attempts 90% of the time
4. **Error Recovery**: Users can recover from errors within one additional command 85% of the time
5. **User Adoption**: 30% of active users try chat commands within first session
6. **User Satisfaction**: Users rate chat functionality 4+ out of 5 stars
