# Implementation Plan: Brew Mode

**Feature:** 3-brew-mode
**Version:** 1.1.0
**Date:** 2026-01-04
**Branch:** `3-brew-mode`

## Technical Context

| Aspect | Decision | Reference |
|--------|----------|-----------|
| Backend | Elixir + Phoenix | Constitution: Boring Technology |
| Frontend | Phoenix LiveView | Existing MVP pattern |
| Database | PostgreSQL | Constitution: Boring Technology |
| AI Provider | Multi-provider (Anthropic, OpenAI, xAI) | research.md v2 |
| Orchestration | Configurable per-agent models | research.md v2 |
| Brew Storage | localStorage (extend deck state) | research.md |
| Agent Config | PostgreSQL + ETS cache | research.md v2 |
| Prompt Storage | Database with UI editor | research.md v2 |

## Constitution Compliance

| Principle | Status | Implementation |
|-----------|--------|----------------|
| Incremental Delivery | ✅ | 6 testable increments below |
| AI-Native Architecture | ✅ | Multi-expert Orchestrator, configurable models, editable prompts |
| Boring Technology | ✅ | Standard Phoenix/LiveView, PostgreSQL, ETS caching |
| Working Code Over Perfect | ✅ | Simple brew structure, provider adapters for extensibility |

## Architecture Overview

```
User Question (in Brew Mode)
         │
         ▼
┌─────────────────────────┐
│    Deck LiveView        │
│  (brew mode toggle)     │
└──────────┬──────────────┘
           │ "submit_brew_question" event
           ▼
┌─────────────────────────┐
│   BrewContext Builder   │
│  (deck + brew + stats)  │
└──────────┬──────────────┘
           │ Rich context object
           ▼
┌─────────────────────────┐
│   AgentConfig           │
│   (from PostgreSQL/ETS) │
│   - model selection     │
│   - system prompt       │
│   - temperature, etc.   │
└──────────┬──────────────┘
           │
           ▼
┌─────────────────────────┐
│   Provider Adapter      │
│  (Anthropic/OpenAI/xAI) │
│   - formats request     │──────► ApiUsageLog (PostgreSQL)
│   - handles differences │
└──────────┬──────────────┘
           │ Synthesized response
           ▼
┌─────────────────────────┐
│  Response Handler       │
│  (parse suggestions)    │
└──────────┬──────────────┘
           │ "expert_response" event
           ▼
┌─────────────────────────┐
│  Chat UI + Brew Panel   │
│  (localStorage sync)    │
└─────────────────────────┘

Admin Flow:
┌─────────────────────────┐
│  /admin/agents          │
│  (LiveView UI)          │
│  - Edit prompts         │
│  - Select models        │
│  - Preview requests     │
└──────────┬──────────────┘
           │ PATCH /admin/agents/:id
           ▼
┌─────────────────────────┐
│  AgentConfig (DB)       │
│  → ETS cache invalidate │
└─────────────────────────┘
```

## Implementation Increments

Each increment is independently testable before proceeding.

### Increment 1: Agent Configuration Infrastructure

**Test:** Create agent config in DB, load from ETS cache, update via API

**Tasks:**
1. Create migration for `agent_configs` table
2. Create migration for `provider_configs` table
3. Create `lib/mtg_deck_builder/ai/agent_config.ex` Ecto schema
4. Create `lib/mtg_deck_builder/ai/provider_config.ex` Ecto schema
5. Create `lib/mtg_deck_builder/ai/agent_registry.ex` for ETS caching
6. Implement `AgentRegistry.start_link/1` to load configs on app start
7. Implement `AgentRegistry.get_agent/1` for cached lookups
8. Implement `AgentRegistry.update_agent/2` with cache invalidation
9. Add AgentRegistry to application supervision tree
10. Seed default agent configs (orchestrator, command_parser)
11. Seed default provider configs (anthropic, openai, xai)

**Artifacts:**
- `priv/repo/migrations/*_create_agent_configs.exs`
- `priv/repo/migrations/*_create_provider_configs.exs`
- `lib/mtg_deck_builder/ai/agent_config.ex`
- `lib/mtg_deck_builder/ai/provider_config.ex`
- `lib/mtg_deck_builder/ai/agent_registry.ex`
- `priv/repo/seeds/agent_seeds.exs`

**Acceptance:**
```elixir
iex> AgentRegistry.get_agent("orchestrator")
%AgentConfig{agent_id: "orchestrator", model: "claude-sonnet-4-20250514", ...}

iex> AgentRegistry.update_agent("orchestrator", %{temperature: 0.5})
{:ok, %AgentConfig{temperature: 0.5, ...}}
```

---

### Increment 2: Provider Adapters

**Test:** Format request correctly for Anthropic, OpenAI, xAI

**Tasks:**
1. Create `lib/mtg_deck_builder/ai/provider_adapter.ex` behaviour
2. Create `lib/mtg_deck_builder/ai/adapters/anthropic.ex` adapter
3. Create `lib/mtg_deck_builder/ai/adapters/openai.ex` adapter
4. Create `lib/mtg_deck_builder/ai/adapters/xai.ex` adapter
5. Implement `format_request/3` for each adapter (handles system prompt placement)
6. Implement `parse_response/1` for each adapter
7. Implement `supports_streaming?/0` for each adapter
8. Create `lib/mtg_deck_builder/ai/ai_client.ex` unified client
9. Implement `AIClient.chat/3` using adapter based on agent config
10. Update existing AnthropicClient to use new adapter pattern
11. Write tests for each adapter's request formatting

**Artifacts:**
- `lib/mtg_deck_builder/ai/provider_adapter.ex`
- `lib/mtg_deck_builder/ai/adapters/anthropic.ex`
- `lib/mtg_deck_builder/ai/adapters/openai.ex`
- `lib/mtg_deck_builder/ai/adapters/xai.ex`
- `lib/mtg_deck_builder/ai/ai_client.ex`
- `test/mtg_deck_builder/ai/adapters/` tests

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

### Increment 3: Brew Data Structures & Storage

**Test:** Create brew, persist to localStorage, reload page, brew intact

**Tasks:**
1. Create `lib/mtg_deck_builder/brew/brew.ex` struct (archetype, key_cards, combos, theme)
2. Create `lib/mtg_deck_builder/brew/combo.ex` struct
3. Add validation functions: `Brew.validate/1`, `Combo.validate/1`
4. Extend deck_storage.js to include brew in deck state
5. Update deck_live.ex assigns: `brew_mode`, `brew`
6. Implement `handle_event("toggle_brew_mode")` in deck_live.ex
7. Add brew_mode and brew to initial deck state initialization
8. Test localStorage persistence of brew data

**Artifacts:**
- `lib/mtg_deck_builder/brew/brew.ex`
- `lib/mtg_deck_builder/brew/combo.ex`
- Updates to `assets/js/hooks/deck_storage.js`
- Updates to `lib/mtg_deck_builder_web/live/deck_live.ex`

**Acceptance:**
```elixir
iex> brew = %Brew{archetype: :control, key_cards: ["Teferi"], combos: [], theme: "UW"}
iex> Brew.validate(brew)
:ok
```
- Toggle brew mode → persist → refresh → brew mode still on with data

---

### Increment 4: Brew Panel UI & Agent Config Admin

**Test:** In Brew Mode, see and edit brew; In admin, edit agent prompts

**Tasks:**
1. Create `lib/mtg_deck_builder_web/components/brew_panel.ex` function component
2. Implement archetype selector dropdown
3. Implement key cards list with add/remove functionality
4. Implement card autocomplete for key cards using existing CardResolver
5. Implement combos list with add/edit/remove functionality
6. Implement theme textarea with character counter
7. Add brew panel to deck_live.html.heex (conditional on brew_mode)
8. Implement handle_events for all brew CRUD operations
9. Add present/missing status indicators for key cards
10. Add complete/incomplete status indicators for combos
11. Style brew panel as collapsible side panel
12. Create `lib/mtg_deck_builder_web/live/admin/agents_live.ex` LiveView
13. Implement agent list view with model/status display
14. Implement agent edit form with system prompt textarea
15. Implement model selector dropdown (filtered by provider)
16. Implement temperature slider
17. Implement reset to default button
18. Implement preview button (shows formatted request)
19. Add route `/admin/agents` to router

**Artifacts:**
- `lib/mtg_deck_builder_web/components/brew_panel.ex`
- `lib/mtg_deck_builder_web/live/admin/agents_live.ex`
- Updates to `lib/mtg_deck_builder_web/live/deck_live.html.heex`
- Updates to `lib/mtg_deck_builder_web/live/deck_live.ex`
- CSS updates for brew panel styling
- Router updates

**Acceptance:**
- Toggle into Brew Mode → see brew panel
- Add archetype "Control" → persists
- Add key card "Lightning Bolt" → appears with present/missing status
- Visit /admin/agents → see all agents
- Edit orchestrator system prompt → saves to DB
- Change orchestrator model to Opus → saves, reflected in subsequent requests

---

### Increment 5: Orchestrator Integration with Configurable Models

**Test:** Ask question in Brew Mode, get expert-synthesized response using configured model

**Tasks:**
1. Create `lib/mtg_deck_builder/brew/brew_context.ex` struct
2. Create `lib/mtg_deck_builder/brew/deck_summary.ex` struct
3. Implement `DeckSummary.build/1` from deck state (mana curve, colors, types, etc.)
4. Implement `BrewContext.build/3` combining brew, deck summary, and question
5. Add missing_key_cards calculation (key cards not in deck)
6. Add incomplete_combos calculation (combos with missing pieces)
7. Create `lib/mtg_deck_builder/brew/context_serializer.ex` for AI prompt formatting
8. Create `lib/mtg_deck_builder/ai/orchestrator.ex` module
9. Implement `Orchestrator.ask/2` using AgentRegistry to get config
10. Use AIClient.chat/3 with appropriate adapter
11. Implement response parsing for suggestions and warnings
12. Update ApiLogger to track model used
13. Implement `handle_event("submit_brew_question")` in deck_live.ex
14. Wire brew question flow: context build → orchestrator → response
15. Add loading state during AI processing
16. Handle API errors with fallback local stats

**Artifacts:**
- `lib/mtg_deck_builder/brew/brew_context.ex`
- `lib/mtg_deck_builder/brew/deck_summary.ex`
- `lib/mtg_deck_builder/brew/context_serializer.ex`
- `lib/mtg_deck_builder/ai/orchestrator.ex`
- Updates to `lib/mtg_deck_builder_web/live/deck_live.ex`

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

### Increment 6: Polish & Integration

**Test:** Full end-to-end Brew Mode experience, graceful degradation

**Tasks:**
1. Add Brew Mode toggle button to deck builder header
2. Ensure normal chat commands still work in Brew Mode
3. Distinguish brew questions vs commands (questions go to Orchestrator, commands use command_parser agent)
4. Add "analyze my deck" as brew question trigger
5. Add "what am I missing?" as brew question trigger
6. Implement graceful AI degradation (show local stats on failure)
7. Add help text explaining Brew Mode features
8. Test brew persistence across format changes
9. Add estimated cost display in admin agent editor
10. Run credo and dialyzer
11. Update README with Brew Mode documentation
12. Update README with agent configuration documentation

**Artifacts:**
- Updates across all components
- README updates
- Final integration testing

**Acceptance:**
- Toggle Brew Mode on/off seamlessly
- Normal commands still work (use command_parser agent config)
- Brew questions get expert responses (use orchestrator agent config)
- AI failure shows local stats fallback
- Data persists correctly
- Admin UI allows full prompt customization

---

## File Structure (New/Modified)

```
lib/
├── mtg_deck_builder/
│   ├── ai/
│   │   ├── agent_config.ex         # NEW: Ecto schema
│   │   ├── provider_config.ex      # NEW: Ecto schema
│   │   ├── agent_registry.ex       # NEW: ETS cache + CRUD
│   │   ├── provider_adapter.ex     # NEW: Behaviour
│   │   ├── adapters/
│   │   │   ├── anthropic.ex        # NEW: Claude adapter
│   │   │   ├── openai.ex           # NEW: OpenAI adapter
│   │   │   └── xai.ex              # NEW: Grok adapter
│   │   ├── ai_client.ex            # NEW: Unified client
│   │   ├── orchestrator.ex         # NEW: Multi-expert AI
│   │   └── anthropic_client.ex     # MODIFIED: Use adapter
│   └── brew/
│       ├── brew.ex                 # NEW: Brew struct
│       ├── combo.ex                # NEW: Combo struct
│       ├── brew_context.ex         # NEW: Context for AI
│       ├── deck_summary.ex         # NEW: Aggregated stats
│       └── context_serializer.ex   # NEW: Prompt formatting
├── mtg_deck_builder_web/
│   ├── live/
│   │   ├── deck_live.ex            # MODIFIED: Brew mode support
│   │   └── admin/
│   │       └── agents_live.ex      # NEW: Agent config UI
│   └── components/
│       └── brew_panel.ex           # NEW: Brew UI component
├── priv/
│   └── repo/
│       ├── migrations/
│       │   ├── *_create_agent_configs.exs   # NEW
│       │   └── *_create_provider_configs.exs # NEW
│       └── seeds/
│           └── agent_seeds.exs     # NEW: Default configs
└── assets/
    └── js/
        └── hooks/
            └── deck_storage.js     # MODIFIED: Brew persistence
```

---

## Default Agent Configurations

| Agent ID | Name | Default Model | Purpose |
|----------|------|---------------|---------|
| `orchestrator` | Orchestrator | claude-sonnet-4-20250514 | Synthesizes expert responses |
| `command_parser` | Command Parser | claude-3-haiku-20240307 | Parses deck commands |
| `mana_expert` | Mana Base Expert | (uses orchestrator) | Mana analysis |
| `synergy_expert` | Synergy Expert | (uses orchestrator) | Card connections |
| `card_eval_expert` | Card Evaluation | (uses orchestrator) | Card roles/upgrades |
| `meta_expert` | Meta Expert | (uses orchestrator) | Format metagame |

**Note:** Expert agents default to using the orchestrator's model. They can be individually configured to use different models if desired.

---

## Dependencies

```elixir
# mix.exs - No new dependencies needed
# Reuses Tesla for API calls (existing)
# Reuses existing card search infrastructure
# May add OpenAI/xAI specific libraries if needed for better integration
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Multiple provider APIs | Complexity | Clean adapter pattern, consistent interface |
| Prompt editing breaks functionality | AI unusable | Default prompt reset button, preview feature |
| ETS cache stale | Wrong config used | Invalidate on update, TTL not needed (explicit invalidation) |
| Sonnet/Opus API costs higher | Budget impact | Show estimated cost in UI, monitor via dashboard |
| Complex orchestrator prompt | Poor responses | Iterate on prompt via UI, A/B test |
| Brew panel clutters UI | UX degradation | Make collapsible; keep minimal per spec |
| Token context too large | API errors | Summarize deck stats efficiently; ~1400 tokens estimated |

---

## Cost Estimates

| Model | Input Cost | Output Cost | Per Question |
|-------|-----------|-------------|--------------|
| Haiku | $0.25/1M | $1.25/1M | ~$0.00003 |
| Sonnet | $3/1M | $15/1M | ~$0.009 |
| Opus | $15/1M | $75/1M | ~$0.045 |

**Default configuration:**
- Command parsing: Haiku (~$0.03/1000 commands)
- Brew questions: Sonnet (~$9/1000 questions)
- Deep analysis: Opus available if user configures (~$45/1000 questions)

---

## Success Criteria Mapping

| Spec Criterion | How Measured |
|----------------|--------------|
| 40% brew adoption | Track brew_mode toggles |
| AI relevance rating | User feedback (future) |
| Response cohesion | Manual QA - sounds like one voice |
| Expert value | Compare with/without brew context |
| Actionability | Suggestions can be acted on |
| Prompt customization | Users can edit prompts in UI |
| Multi-model support | Different models configurable per agent |

---

## Next Steps After Plan

1. `/speckit.tasks` - Generate detailed task list from this plan
2. `/speckit.taskstoissues` - Create GitHub issues from tasks
3. Begin Increment 1 implementation (Agent Config Infrastructure)
