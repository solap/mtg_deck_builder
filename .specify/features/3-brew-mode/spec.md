# Feature Specification: Brew Mode

**Version:** 1.3.0
**Created:** 2026-01-04
**Updated:** 2026-01-04
**Status:** Draft

## Overview

Brew Mode gives AI agents the strategic context they need to provide **smart, thoughtful suggestions**. Each deck has one **Brew** - optional sections that capture what matters to the strategy.

The brew sections:
- **Archetype** (optional): Control, Aggro, Midrange, Combo, Tempo, Ramp, etc.
- **Key Cards** (optional): Important cards the deck is built around
- **Combos** (optional): Multi-card interactions the deck aims to assemble
- **Theme** (optional): Free-text description of the deck's identity

**Core principle**: The brew is primarily *input for AI*, not a dashboard. Keep the UI minimal - only show information that's actually useful. The value is in AI agents using this context to come up with clever ideas and answer questions thoughtfully.

### Multi-Agent Philosophy

The magic happens when **multiple specialized experts collaborate** to give cohesive, thoughtful advice - similar to how Claude Code melds different voices into one strong experience. Rather than a single AI giving generic answers, Brew Mode orchestrates specialized agents:

**Core Experts** (frequently consulted):
- **Mana Base**: Land counts, color sources, curve alignment
- **Synergy & Interactions**: Card connections, combos, "secret tech", what unlocks what
- **Card Evaluation**: Card roles, upgrades, "X is better than Y because..."
- **Meta & Matchups**: Format positioning, popular decks, hate cards

**Situational Experts** (consulted when relevant):
- **Win Condition**: How the deck closes games, backup plans
- **Budget**: Affordable alternatives, cost optimization
- **Curve & Tempo**: Turn-by-turn sequencing, mana efficiency
- **Consistency**: Redundancy, tutors, reliable execution
- **Sideboard**: 15-card construction, matchup-specific swaps
- **Rules & Interactions**: Complex rules, combo verification

**Validators** (mechanical checks):
- **Format Legality**: Ensures all cards are legal in chosen format

These experts **don't speak directly to the user**. Instead, an **Orchestrator** intelligently selects which experts to consult based on the question, then synthesizes their insights into a unified, natural response. The user experiences one helpful assistant that happens to be deeply knowledgeable across multiple domains.

## Clarifications

### Session 2026-01-04
- Q: What types of strategic pillars should be supported? → A: Cards + Combos + Themes - Pillars can be key cards, multi-card combos, or strategic themes
- Q: Should Brew Mode be a single deck identity or multiple pillars? → A: Single Deck Identity - One "brew profile" with optional sections: Archetype, Key Cards list, Combos list, Theme description
- Q: What archetype-specific stats should be displayed? → A: Minimal, archetype-specific key metrics only. Focus is on AI agents using profile context to give smart suggestions, not on showing stats. Only present data that's actually useful.
- Q: How should users enter/activate Brew Mode? → A: Toggle to a separate layout. Brew Mode shows brew profile panel alongside existing functionality (chat, card management, deck list). All normal operations still work.
- Q: What is the relationship between a brew and a deck? → A: 1 deck = 1 brew. Each deck has one brew (its strategic context). Simple model.
- Q: How should AI agents interact? → A: Multiple specialized experts (mana, synergy, meta, win conditions) collaborate behind the scenes. An Orchestrator synthesizes their insights into one cohesive, natural response. User experiences one helpful assistant, not a committee.
- Q: Should we have more specialized experts consulted situationally? → A: Yes. Core experts (Mana Base, Synergy & Interactions, Card Evaluation, Meta & Matchups) are frequently consulted. Situational experts (Win Condition, Budget, Curve & Tempo, Consistency, Sideboard, Rules & Interactions) are consulted when relevant. Format Legality is a validator, not an expert.
- Q: Can different agents use different models? → A: Yes. Each agent/sub-agent can be configured to use a different model (Claude Haiku, Sonnet, Opus, or other providers). This allows cost/quality optimization per task.
- Q: Where should system prompts be stored? → A: In the UI, editable by users. Prompts stored in database, accessible via admin/settings panel. Both developers and users can tune prompts.
- Q: How to handle different model prompt formats? → A: Abstract prompt handling to account for different model preferences (system prompt placement, context window, history format). Some models prefer system in first message, others as separate parameter.

## Problem Statement

Current deck building in the app is card-by-card without understanding the builder's intent. Users may have a specific strategy in mind (e.g., "Superfriends planeswalker deck" or "Enchantress combo") but the system doesn't know this context. This leads to:
- AI chat commands that lack strategic context
- No way to track whether the deck aligns with original goals
- Card suggestions that don't consider the overall strategy

## Target Users

### Primary Users
- **Deck Brewers**: Players who design decks around specific combos, themes, or strategies
- **Creative Players**: Those who want to build around unusual card interactions
- **Competitive Players**: Those optimizing decks for specific win conditions

### Secondary Users
- **New Players**: Can learn deck building by seeing explicit strategic structure
- **Content Creators**: Can document and share their brewing process

## User Scenarios & Testing

### Scenario 1: Create Brew
**As a** deck brewer
**I want to** define my deck's strategic identity through a brew
**So that** the AI and I have shared context about what I'm trying to build

**Acceptance Criteria:**
- User can enter Brew Mode from the main deck builder
- User can optionally select an archetype (Control, Aggro, Midrange, Combo, Tempo, Ramp)
- User can optionally add key cards (important cards the deck is built around)
- User can optionally add combos (2-4 card interactions)
- User can optionally add a theme description (free text)
- Brew is visible while building the deck
- All sections are optional - user fills in what matters to them

### Scenario 2: Brew-Aware Card Addition
**As a** deck brewer
**I want to** add cards with awareness of my brew
**So that** my deck stays focused on its core strategy

**Acceptance Criteria:**
- AI chat commands consider brew when suggesting cards
- User can ask "suggest cards for my combo" or "what fits my archetype"
- Key cards from brew are highlighted if not yet in deck ("missing key card")

### Scenario 3: AI-Powered Strategy Help
**As a** deck brewer
**I want to** ask the AI for help based on my brew
**So that** I get smart, context-aware suggestions

**Acceptance Criteria:**
- User can ask "what am I missing?" and AI considers brew
- User can ask "suggest cards for my [archetype/combo/theme]"
- AI references brew context in its suggestions (e.g., "since you're building control...")

### Scenario 4: Multi-Expert Analysis
**As a** deck brewer
**I want to** get comprehensive feedback that considers multiple aspects of my deck
**So that** I don't miss important considerations (mana, synergy, win conditions, etc.)

**Acceptance Criteria:**
- When user asks broad questions like "analyze my deck" or "what should I change?"
- Response synthesizes insights from multiple expert perspectives
- User receives one cohesive answer (not separate responses from each expert)
- Response is conversational and helpful, not a checklist of expert opinions
- Expert perspectives are weighted by relevance to the user's brew and question

## Functional Requirements

### FR1: Brew Mode Layout
- FR1.1: System SHALL provide a "Brew Mode" toggle in the deck builder header
- FR1.2: System SHALL switch to Brew Mode layout when toggled, showing brew panel
- FR1.3: System SHALL retain all normal functionality in Brew Mode (chat, search, card management, deck list)
- FR1.4: System SHALL persist brew data with deck state (survives page refresh, mode toggle)
- FR1.5: System SHALL allow toggling back to normal layout while preserving brew data

### FR2: Brew Structure
- FR2.1: System SHALL store one brew per deck
- FR2.2: System SHALL allow an optional archetype selection from: Control, Aggro, Midrange, Combo, Tempo, Ramp
- FR2.3: System SHALL allow an optional key cards list (references to specific cards)
- FR2.4: System SHALL allow an optional combos list (each combo references 2-4 cards)
- FR2.5: System SHALL allow an optional theme description (free text, max 500 characters)
- FR2.6: System SHALL validate that card references in key cards and combos exist in the database
- FR2.7: System SHALL allow editing any brew section at any time

### FR3: Brew Display (Minimal)
- FR3.1: System SHALL display brew in a compact, collapsible panel
- FR3.2: System SHALL show key cards with present/missing status
- FR3.3: System SHALL show combos with complete/incomplete status
- FR3.4: System SHALL show archetype and theme as simple labels (no stats dashboard)

### FR4: AI Integration (Primary Value)
- FR4.1: System SHALL pass full brew context to AI chat commands
- FR4.2: System SHALL enable AI to give context-aware suggestions based on archetype, key cards, combos, and theme
- FR4.3: System SHALL support natural queries like "what supports my combo?", "suggest finishers for control", "what am I missing?"
- FR4.4: System SHALL allow AI to proactively mention brew alignment when relevant (e.g., "this card synergizes with your key card X")

### FR5: Multi-Agent Orchestration
- FR5.1: System SHALL support multiple specialized expert agents, each with domain expertise
- FR5.2: System SHALL include an Orchestrator that coordinates expert consultations
- FR5.3: System SHALL route user questions to relevant experts based on question type and brew context
- FR5.4: System SHALL synthesize expert insights into a single, cohesive response
- FR5.5: System SHALL present responses in a unified voice (user never sees "Expert X says...")
- FR5.6: System SHALL weight expert contributions by relevance to the specific question
- FR5.7: System SHALL allow experts to surface concerns even when not directly asked (e.g., mana expert noting issues)

### FR6: Expert Domains

#### Core Experts (frequently consulted)
- FR6.1: **Mana Base Expert** SHALL analyze land count, color sources, curve alignment, mana fixing needs, color pip requirements
- FR6.2: **Synergy & Interactions Expert** SHALL identify card connections, non-obvious combos, enablers, "secret tech", cards that unlock other cards (e.g., "Urza needs fast mana")
- FR6.3: **Card Evaluation Expert** SHALL understand card roles, suggest upgrades, explain "X is better than Y for this purpose", identify strictly-better alternatives
- FR6.4: **Meta & Matchups Expert** SHALL know format metagame, popular decks, hate cards, how to position against the field, sideboard priorities

#### Situational Experts (consulted when relevant)
- FR6.5: **Win Condition Expert** SHALL evaluate how the deck closes games, backup plans, inevitability, clock speed, alternate win cons
- FR6.6: **Budget Expert** SHALL know card prices, suggest affordable alternatives, optimize within cost constraints
- FR6.7: **Curve & Tempo Expert** SHALL analyze turn-by-turn sequencing, mana efficiency, threat/answer timing, aggro pacing
- FR6.8: **Consistency Expert** SHALL evaluate redundancy, tutors, card selection, ensuring the deck reliably executes its plan
- FR6.9: **Sideboard Expert** SHALL advise on 15-card construction, in/out decisions per matchup, transformational sideboards
- FR6.10: **Rules & Interactions Expert** SHALL clarify complex rules interactions, layers, triggers, combo verification

#### Validators (mechanical checks)
- FR6.11: **Format Legality Validator** SHALL verify all cards are legal in chosen format, flag banned/restricted cards, enforce copy limits

#### Expert Behavior
- FR6.12: Each expert SHALL have access to brew context (archetype, key cards, combos, theme)
- FR6.13: Each expert SHALL consider the current deck state when providing insights
- FR6.14: Orchestrator SHALL select which experts to consult based on question type, brew context, and deck state
- FR6.15: Not all experts need to be consulted for every question - Orchestrator uses judgment

### FR7: Response Quality
- FR7.1: System SHALL produce responses that feel like one knowledgeable person, not a committee
- FR7.2: System SHALL prioritize actionable insights over comprehensive analysis
- FR7.3: System SHALL adapt tone to question type (casual chat vs deep analysis)
- FR7.4: System SHALL avoid overwhelming users with too many suggestions at once
- FR7.5: System SHALL explain reasoning when making non-obvious suggestions

### FR8: Agent Configuration
- FR8.1: System SHALL store agent configurations in PostgreSQL database
- FR8.2: System SHALL allow each agent to be configured with a different AI model (provider + model name)
- FR8.3: System SHALL provide a UI for viewing and editing agent system prompts
- FR8.4: System SHALL support at minimum: Claude (Haiku, Sonnet, Opus), with extensibility for other providers
- FR8.5: System SHALL store system prompts as editable text, version-controlled with updated_at timestamps
- FR8.6: System SHALL abstract prompt formatting to handle different model conventions:
  - Claude: system parameter separate from messages
  - OpenAI: system role in messages array
  - Others: configurable per provider
- FR8.7: System SHALL allow agents to have different context window limits and handle truncation appropriately
- FR8.8: System SHALL provide default prompts for each agent, restorable if user edits go wrong

### FR9: Agent Registry
- FR9.1: System SHALL maintain a registry of all agents with their roles and configurations
- FR9.2: System SHALL include the following configurable agents:
  - **Orchestrator**: Synthesizes expert responses (default: Sonnet)
  - **Command Parser**: Parses deck commands (default: Haiku)
  - **Mana Base Expert**: Mana analysis (default: uses Orchestrator)
  - **Synergy Expert**: Card connections (default: uses Orchestrator)
  - **Card Evaluation Expert**: Card roles and upgrades (default: uses Orchestrator)
  - **Meta Expert**: Format metagame (default: uses Orchestrator)
  - **[Situational Experts]**: Each can have own config or inherit from Orchestrator
- FR9.3: System SHALL allow disabling individual experts
- FR9.4: System SHALL show estimated cost per agent based on model selection

## Edge Cases & Error Handling

### Brew Management
- Empty brew: Allow - all sections are optional
- Invalid card reference: Show error, prevent saving until corrected
- Card removed from database: Show "card not found" warning in brew

### Key Cards & Combos
- Key card removed from deck: Show as "missing" in brew panel
- Combo piece removed from deck: Show as "incomplete combo" in brew panel
- Duplicate card in key cards list: Prevent duplicates
- Combo with fewer than 2 cards: Require minimum 2 cards for combo

### Multi-Agent Handling
- Expert disagrees with another: Orchestrator resolves conflicts, presents balanced view
- No experts have relevant input: Provide general helpful response, don't force expert perspectives
- User asks very specific question: Route to most relevant expert, don't consult all
- Expert response times out: Continue with available expert input, don't block response
- Contradictory advice: Orchestrator acknowledges trade-offs rather than hiding disagreement

## Non-Functional Requirements

### Performance
- Brew operations SHALL complete within 200ms
- Strategy alignment checks SHALL update within 500ms of deck changes

### Usability
- Brew panel SHALL be collapsible to not obstruct deck building
- Missing key cards and combo pieces SHALL be visually distinct (color/icon)

## Assumptions

- Users understand their deck's strategic goals
- Archetypes (Control, Aggro, etc.) are familiar to MTG players
- Key cards and combos are natural ways to describe deck strategy
- Users will fill in brew sections that matter to them (not all)

## Out of Scope (This Phase)

- AI auto-generating brew from deck contents
- Brew templates (pre-filled brews for common archetypes)
- Sharing brews between decks
- Community-suggested combos or key cards
- Archetype-specific card suggestions (e.g., "best control finishers")

## Dependencies

- Phase 2 AI Chat Commands (complete)
- Existing deck state management
- Card database with search

## Success Criteria

1. **Brew Adoption**: 40% of users who enter Brew Mode fill in at least one brew section
2. **Strategy Clarity**: Users report better understanding of their deck's focus
3. **AI Relevance**: AI suggestions with brew context are rated more relevant than without
4. **Completion Tracking**: Users with key cards/combos defined complete those pieces 80% of the time
5. **Response Cohesion**: Users perceive AI as one knowledgeable assistant (not fragmented experts)
6. **Expert Value**: Multi-expert analysis catches issues single-perspective AI would miss 70% of the time
7. **Actionability**: 80% of AI suggestions are actionable (user can immediately act on them)
