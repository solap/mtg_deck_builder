# Tasks: Brew Mode

**Feature:** 3-brew-mode
**Generated:** 2026-01-04
**Spec Version:** 1.3.0
**Plan Version:** 1.1.0

## Overview

This task list implements Brew Mode with multi-model agent configuration, editable system prompts, and provider-agnostic adapters.

**User Stories (from spec.md):**
- US1: Create Brew - Define deck's strategic identity through a brew
- US2: Brew-Aware Card Addition - Add cards with awareness of brew context
- US3: AI-Powered Strategy Help - Ask AI for help based on brew
- US4: Multi-Expert Analysis - Get comprehensive feedback from multiple expert perspectives

**Key Features (v1.1.0):**
- Multi-model support (Anthropic, OpenAI, xAI) with configurable per-agent
- Editable system prompts stored in PostgreSQL with UI editor
- Provider adapters handling different API conventions
- ETS caching for fast config lookups

---

## Phase 1: Setup

**Goal:** Verify environment and create feature branch
**Test:** `mix compile` succeeds
**Dependencies:** Phase 2 AI Chat Commands complete

- [X] T001 Verify Phoenix/Elixir development environment is ready
- [X] T002 Create feature branch `3-brew-mode` from main
- [X] T003 [P] Review existing AI infrastructure in `lib/mtg_deck_builder/ai/`
- [X] T004 [P] Verify existing CardResolver module exists in `lib/mtg_deck_builder/chat/card_resolver.ex`

**Acceptance:** Branch created, dependencies verified

---

## Phase 2: Agent Configuration Infrastructure (Increment 1)

**Goal:** Create agent configs in DB, load from ETS cache, update via API
**Test:** `AgentRegistry.get_agent("orchestrator")` returns config; update invalidates cache
**Dependencies:** Phase 1 complete

### Database Migrations

- [X] T005 [P] Create migration for `agent_configs` table in `priv/repo/migrations/*_create_agent_configs.exs`
- [X] T006 [P] Create migration for `provider_configs` table in `priv/repo/migrations/*_create_provider_configs.exs`

### Ecto Schemas

- [X] T007 [P] Create `lib/mtg_deck_builder/ai/agent_config.ex` Ecto schema with all fields from data-model.md
- [X] T008 [P] Create `lib/mtg_deck_builder/ai/provider_config.ex` Ecto schema

### ETS Cache Layer

- [X] T009 Create `lib/mtg_deck_builder/ai/agent_registry.ex` GenServer with ETS table
- [X] T010 Implement `AgentRegistry.start_link/1` to load configs from DB on startup
- [X] T011 Implement `AgentRegistry.get_agent/1` for cached lookups by agent_id
- [X] T012 Implement `AgentRegistry.list_agents/0` to get all agent configs
- [X] T013 Implement `AgentRegistry.update_agent/2` with database update and cache invalidation
- [X] T014 Implement `AgentRegistry.reset_agent_prompt/1` to restore default_prompt
- [X] T015 Add AgentRegistry to application supervision tree in `lib/mtg_deck_builder/application.ex`

### Seed Data

- [X] T016 Create `priv/repo/seeds/agent_seeds.exs` with default agent configs (orchestrator, command_parser)
- [X] T017 Add seed data for provider configs (anthropic, openai, xai) in `priv/repo/seeds/agent_seeds.exs`
- [X] T018 Update `priv/repo/seeds.exs` to include agent seeds
- [X] T019 Run migrations and verify seed data loads correctly

**Acceptance:**
```elixir
iex> AgentRegistry.get_agent("orchestrator")
%AgentConfig{agent_id: "orchestrator", model: "claude-sonnet-4-20250514", ...}

iex> AgentRegistry.update_agent("orchestrator", %{temperature: 0.5})
{:ok, %AgentConfig{temperature: 0.5, ...}}
```

---

## Phase 3: Provider Adapters (Increment 2)

**Goal:** Format requests correctly for Anthropic, OpenAI, xAI with provider-specific conventions
**Test:** Each adapter formats requests according to provider conventions
**Dependencies:** Phase 2 complete

### Adapter Behaviour

- [X] T020 Create `lib/mtg_deck_builder/ai/provider_adapter.ex` behaviour with callbacks: format_request/3, parse_response/1, supports_streaming?/0

### Provider Implementations

- [X] T021 [P] Create `lib/mtg_deck_builder/ai/adapters/anthropic.ex` implementing ProviderAdapter
- [X] T022 [P] Create `lib/mtg_deck_builder/ai/adapters/openai.ex` implementing ProviderAdapter
- [X] T023 [P] Create `lib/mtg_deck_builder/ai/adapters/xai.ex` implementing ProviderAdapter
- [X] T024 Implement `format_request/3` for Anthropic adapter (system as separate `system` param)
- [X] T025 Implement `format_request/3` for OpenAI adapter (system as first message with role: "system")
- [X] T026 Implement `format_request/3` for xAI adapter (OpenAI-compatible format)
- [X] T027 Implement `parse_response/1` for each adapter to normalize responses
- [X] T028 Implement `supports_streaming?/0` for each adapter

### Unified Client

- [X] T029 Create `lib/mtg_deck_builder/ai/ai_client.ex` unified client module
- [X] T030 Implement `AIClient.chat/3` that selects adapter based on agent config provider
- [X] T031 Implement `AIClient.get_adapter/1` to resolve adapter module from provider string
- [X] T032 Update existing `lib/mtg_deck_builder/ai/anthropic_client.ex` to use new adapter pattern

**Acceptance:**
```elixir
# Anthropic: system prompt as separate param
iex> Anthropic.format_request("System prompt", messages, opts)
%{system: "System prompt", messages: [...], model: "claude-sonnet-4-20250514"}

# OpenAI: system prompt as first message
iex> OpenAI.format_request("System prompt", messages, opts)
%{messages: [%{role: "system", content: "System prompt"}, ...], model: "gpt-4-turbo"}
```

---

## Phase 4: Brew Data Structures & Storage (Increment 3)

**Goal:** Create brew, persist to localStorage, reload page with brew intact
**Test:** Toggle brew mode → persist → refresh → brew mode still on with data
**Dependencies:** Phase 3 complete

### Elixir Structs

- [X] T033 [P] Create `lib/mtg_deck_builder/brew/brew.ex` struct with archetype, key_cards, combos, theme
- [X] T034 [P] Create `lib/mtg_deck_builder/brew/combo.ex` struct with cards, description
- [X] T035 Implement `Brew.validate/1` with all validation rules from data-model.md
- [X] T036 Implement `Combo.validate/1` requiring 2-4 cards, description max 200 chars
- [X] T037 Implement `Brew.new/0` returning empty brew with defaults

### LiveView State

- [X] T038 Add `brew_mode` and `brew` assigns to `lib/mtg_deck_builder_web/live/deck_live.ex`
- [X] T039 Implement `handle_event("toggle_brew_mode")` in deck_live.ex
- [X] T040 Initialize brew_mode and brew in mount/3 from client state
- [X] T041 Initialize empty brew when entering Brew Mode if none exists

### JavaScript Storage

- [X] T042 Extend `assets/js/hooks/deck_storage.js` to include brew_mode and brew in deck state
- [X] T043 Add sync_deck push after brew changes to persist to localStorage

**Acceptance:**
```elixir
iex> brew = %Brew{archetype: :control, key_cards: ["Teferi"], combos: [], theme: "UW"}
iex> Brew.validate(brew)
:ok
```
- Toggle brew mode → persist → refresh → brew mode still on with data

---

## Phase 5: Brew Panel UI & Agent Config Admin (Increment 4)

**Goal:** In Brew Mode, see and edit brew; In admin, edit agent prompts
**Test:** Brew panel shows; Admin allows editing prompts and models
**Dependencies:** Phase 4 complete

### Brew Panel Component

- [X] T044 [US1] Create `lib/mtg_deck_builder_web/components/brew_panel.ex` function component
- [X] T045 [US1] Implement archetype selector dropdown in brew_panel.ex
- [X] T046 [US1] Implement key cards list with add/remove functionality
- [X] T047 [US1] Implement card autocomplete for key cards using existing CardResolver
- [X] T048 [US1] Implement combos list with add/edit/remove functionality
- [X] T049 [US1] Implement theme textarea with character counter (500 char limit)
- [X] T050 [US1] Add present/missing status indicators for key cards
- [X] T051 [US1] Add complete/incomplete status indicators for combos
- [X] T052 [US1] Style brew panel as collapsible side panel with CSS

### Deck LiveView Events

- [X] T053 [US1] Add brew panel to `lib/mtg_deck_builder_web/live/deck_live.html.heex` conditional on brew_mode
- [X] T054 [US1] Implement `handle_event("update_brew_archetype")` in deck_live.ex
- [X] T055 [US1] Implement `handle_event("add_key_card")` with validation in deck_live.ex
- [X] T056 [US1] Implement `handle_event("remove_key_card")` in deck_live.ex
- [X] T057 [US1] Implement `handle_event("add_combo")` with validation in deck_live.ex
- [X] T058 [US1] Implement `handle_event("remove_combo")` in deck_live.ex
- [X] T059 [US1] Implement `handle_event("update_combo")` in deck_live.ex
- [X] T060 [US1] Implement `handle_event("update_theme")` with 500 char limit in deck_live.ex
- [X] T061 [US1] Implement `handle_event("search_cards_for_brew")` for autocomplete

### Key Card & Combo Status

- [X] T062 [US2] Create helper function calculate_key_card_status/2 in deck_live.ex
- [X] T063 [US2] Create helper function calculate_combo_status/2 in deck_live.ex
- [X] T064 [US2] Update status on deck changes (add_card, remove_card events)

### Agent Admin UI

- [X] T065 Create `lib/mtg_deck_builder_web/live/admin/agents_live.ex` LiveView
- [X] T066 Implement agent list view with model/status display
- [X] T067 Implement agent edit form with system prompt textarea
- [X] T068 Implement model selector dropdown (filtered by provider)
- [X] T069 Implement temperature slider (0.0 - 2.0)
- [X] T070 Implement reset to default button
- [X] T071 Implement preview button (shows formatted request with sample context)
- [X] T072 Add estimated cost display based on model selection
- [X] T073 Add route `/admin/agents` to `lib/mtg_deck_builder_web/router.ex`

**Acceptance:**
- Toggle into Brew Mode → see brew panel
- Add archetype "Control" → persists
- Add key card "Lightning Bolt" → appears with present/missing status
- Visit /admin/agents → see all agents
- Edit orchestrator system prompt → saves to DB
- Change orchestrator model to Opus → saves, reflected in subsequent requests

---

## Phase 6: Orchestrator Integration (Increment 5)

**Goal:** Ask question in Brew Mode, get expert-synthesized response using configured model
**Test:** Ask question → get response; Change model in admin → next question uses new model
**Dependencies:** Phase 5 complete

### Context Building

- [X] T074 [US3] Create `lib/mtg_deck_builder/brew/brew_context.ex` struct
- [X] T075 [US3] Create `lib/mtg_deck_builder/brew/deck_summary.ex` struct
- [X] T076 [US3] Implement `DeckSummary.build/2` from deck state (mana curve, colors, types, land count)
- [X] T077 [US3] Implement `BrewContext.build/3` combining brew, deck summary, and question
- [X] T078 [US3] Add missing_key_cards calculation (key cards not in deck)
- [X] T079 [US3] Add incomplete_combos calculation (combos with missing pieces)

### Context Serialization

- [X] T080 [US3] Create `lib/mtg_deck_builder/brew/context_serializer.ex` module
- [X] T081 [US3] Implement `ContextSerializer.to_prompt/1` formatting BrewContext for AI

### Orchestrator Module

- [X] T082 [US3] Create `lib/mtg_deck_builder/ai/orchestrator.ex` module
- [X] T083 [US3] Implement `Orchestrator.ask/2` using AgentRegistry to get orchestrator config
- [X] T084 [US3] Use AIClient.chat/3 with appropriate adapter based on config
- [X] T085 [US3] Implement response parsing for suggestions and warnings
- [X] T086 [US3] Update ApiUsageLog to track model used for orchestrator requests

### LiveView Integration

- [X] T087 [US3] Implement `handle_event("submit_brew_question")` in deck_live.ex
- [X] T088 [US3] Build BrewContext from current brew and deck state
- [X] T089 [US3] Wire brew question flow: context build → orchestrator → response
- [X] T090 [US3] Add loading state during AI processing (`ai_processing` assign)
- [X] T091 [US3] Handle API errors with fallback local stats display

**Acceptance:**
```elixir
iex> context = BrewContext.build(brew, deck, "What should I add?")
iex> {:ok, response} = Orchestrator.ask(context, format: :modern)
iex> response.content
"For your control deck..."
```
- Ask question in Brew Mode → see loading indicator → receive response
- Change orchestrator model in admin → next question uses new model

---

## Phase 7: Polish & Integration (Increment 6)

**Goal:** Full end-to-end Brew Mode experience, graceful degradation
**Test:** Toggle on/off, commands work, AI failure graceful, credo/dialyzer pass
**Dependencies:** All previous phases complete

### UI Polish

- [X] T092 Add Brew Mode toggle button to deck builder header in deck_live.html.heex
- [X] T093 Add help text explaining Brew Mode features
- [X] T094 Ensure normal chat commands still work in Brew Mode

### Command Routing

- [X] T095 [US4] Distinguish brew questions vs commands (questions → Orchestrator, commands → command_parser)
- [X] T096 [US4] Add "analyze my deck" as brew question trigger
- [X] T097 [US4] Add "what am I missing?" as brew question trigger

### Error Handling

- [X] T098 [US4] Implement graceful AI degradation (show local stats on failure)
- [X] T099 [US4] Test brew persistence across format changes

### Code Quality

- [X] T100 Run `mix credo --strict` and fix all warnings
- [X] T101 Run `mix dialyzer` and fix all type issues

### Documentation

- [X] T102 Update README.md with Brew Mode documentation
- [X] T103 Update README.md with agent configuration documentation

**Acceptance:**
- Toggle Brew Mode on/off seamlessly
- Normal commands still work (use command_parser agent config)
- Brew questions get expert responses (use orchestrator agent config)
- AI failure shows local stats fallback
- Data persists correctly
- Admin UI allows full prompt customization

---

## Dependencies Graph

```
Phase 1 (Setup)
    │
    ▼
Phase 2 (Agent Config) ─────────────────┐
    │                                    │
    ▼                                    │
Phase 3 (Provider Adapters) ◄────────────┘
    │
    ├───────────────────────────────────┐
    │                                    │
    ▼                                    ▼
Phase 4 (Brew Structs)          Phase 5 UI can start
    │                            without AI integration
    │
    ▼
Phase 5 (Brew Panel UI + Admin)
    │
    ▼
Phase 6 (Orchestrator Integration)
    │
    ▼
Phase 7 (Polish)
```

---

## Parallel Execution Opportunities

### Phase 2 (Agent Config):
- T005 + T006: Both migrations can be created in parallel
- T007 + T008: Both schemas can be created in parallel

### Phase 3 (Provider Adapters):
- T021 + T022 + T023: All three adapter files can be created in parallel

### Phase 4 (Brew Structs):
- T033 + T034: Brew and Combo structs can be created in parallel

### Phase 5 (UI):
- T044-T064 (Brew Panel) + T065-T073 (Admin UI): Can be developed in parallel

---

## Summary

| Phase | Tasks | Description |
|-------|-------|-------------|
| Phase 1 | 4 | Setup |
| Phase 2 | 15 | Agent Configuration Infrastructure |
| Phase 3 | 13 | Provider Adapters |
| Phase 4 | 11 | Brew Data Structures & Storage |
| Phase 5 | 30 | Brew Panel UI & Agent Config Admin |
| Phase 6 | 18 | Orchestrator Integration |
| Phase 7 | 12 | Polish & Integration |
| **Total** | **103** | |

---

## Implementation Strategy

1. **MVP Scope:** Phases 1-4 (43 tasks) - Agent config infrastructure + Provider adapters + Brew data structures
2. **First Milestone:** Agents configurable in DB, adapters working, brew can be created/persisted
3. **Incremental Delivery:** Each phase is independently testable per plan.md increments
4. **Risk Mitigation:** Provider adapters enable model switching without code changes; ETS cache ensures fast lookups
