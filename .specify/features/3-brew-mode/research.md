# Research: Brew Mode

**Feature:** 3-brew-mode
**Date:** 2026-01-04

## Research Summary

This document captures technical decisions and research findings for implementing Brew Mode - a strategic context layer that enables multi-agent AI collaboration for intelligent deck building assistance.

---

## 1. Multi-Agent Orchestration Architecture

### Decision: Orchestrator Pattern with Prompt-Based Experts

**Rationale:**
- Spec requires experts to "not speak directly to user" - Orchestrator synthesizes
- Each expert is a specialized prompt, not a separate model/service
- Single Claude API call with rich system prompt for Orchestrator
- Orchestrator decides which expert "voices" to include based on question
- Produces cohesive response in unified voice

**Alternatives Considered:**
- Separate API calls per expert: Expensive, slow, harder to synthesize
- RAG with expert embeddings: Overkill for defined domain knowledge
- Hardcoded expert rules: Too rigid, loses natural language flexibility
- Parallel expert calls then merge: Complex orchestration, race conditions

**Implementation Notes:**
- Orchestrator system prompt contains all expert personas and domains
- User question + brew context + deck state sent as single request
- Response is already synthesized - no post-processing needed
- Use Claude Sonnet for quality synthesis (vs Haiku for simple commands)

**Orchestrator Prompt Structure:**
```
You are a Magic: The Gathering deck building advisor with deep expertise across multiple domains.

When answering questions, draw from your knowledge as:
- **Mana Base Expert**: Land counts, color sources, curve alignment...
- **Synergy Expert**: Card connections, combos, enablers...
- **Card Evaluation Expert**: Card roles, upgrades, alternatives...
- **Meta Expert**: Format metagame, popular decks, hate cards...
[... situational experts as needed ...]

Context about this deck:
- Archetype: {archetype}
- Key Cards: {key_cards}
- Combos: {combos}
- Theme: {theme}
- Current deck state: {deck_summary}

Guidelines:
- Respond in a unified, conversational voice
- Don't say "The mana expert suggests..." - just give the advice
- Weight perspectives by relevance to the question
- Prioritize actionable insights
- Acknowledge trade-offs when experts might "disagree"
```

---

## 2. Expert Selection Strategy

### Decision: Implicit Selection via Rich Context (No Routing Logic)

**Rationale:**
- Claude naturally weighs expert perspectives based on question type
- Explicit routing adds complexity without clear benefit
- All expert knowledge available in system prompt
- Model inference handles relevance weighting

**Alternatives Considered:**
- Pre-classification then expert selection: Extra API call, overhead
- Keyword-based routing: Brittle, misses nuanced questions
- User selects experts: Adds UI complexity, users don't know what they need

**Implementation Notes:**
- Include all core expert personas in every request
- Include situational experts when brew context suggests relevance:
  - Budget Expert: if user mentions budget/price constraints
  - Sideboard Expert: if question mentions sideboard/matchups
  - Rules Expert: if question asks about interactions/triggers
- Validator (Format Legality) runs separately as mechanical check

---

## 3. Brew Data Storage

### Decision: Extend Existing localStorage Deck State

**Rationale:**
- MVP uses localStorage for deck persistence - brew is part of deck
- 1 deck = 1 brew means brew is a property of deck state
- No auth system yet = no user-specific server storage
- Consistent with "boring technology" principle

**Alternatives Considered:**
- Separate localStorage key: Complicates state management
- PostgreSQL: Requires auth system (Phase 9)
- Session-only: Lost on refresh, poor UX

**Implementation Notes:**
- Extend deck state structure:
```javascript
{
  format: "modern",
  mainboard: [...],
  sideboard: [...],
  removed: [...],
  brew: {
    archetype: "control",  // optional
    keyCards: ["Teferi, Hero of Dominaria", "Supreme Verdict"],  // optional
    combos: [
      { cards: ["Splinter Twin", "Deceiver Exarch"], description: "Infinite tokens" }
    ],  // optional
    theme: "UW Control focusing on planeswalker win conditions"  // optional, max 500 chars
  }
}
```
- Sync brew changes via existing deck_storage.js hook

---

## 4. Key Cards & Combo Card References

### Decision: Store Card Names, Validate Against Database

**Rationale:**
- Storing scryfall_id would require lookup on every display
- Card names are human-readable and stable
- Validation on add ensures cards exist
- Simple to check "is card in deck?" for presence status

**Alternatives Considered:**
- Store card IDs only: Requires join on display
- Store full card objects: Wasteful, stale data risk
- No validation: Could have invalid card references

**Implementation Notes:**
- On brew edit, validate card names against cards table
- Use existing CardResolver.resolve/2 for fuzzy matching
- Store normalized card name (exact match from DB)
- Combo validation: 2-4 cards required per combo

---

## 5. Brew Panel UI Architecture

### Decision: Collapsible Side Panel in Toggle Layout

**Rationale:**
- Spec says "toggle to separate layout" with brew visible
- Collapsible keeps it out of the way when not needed
- Retains all normal functionality (chat, search, deck list)
- Compact display fits alongside existing UI

**Alternatives Considered:**
- Full-page brew editor: Loses deck context
- Modal overlay: Blocks deck interaction
- Tab-based view: Requires more clicks to switch

**Implementation Notes:**
- New LiveView assign: `brew_mode: boolean`
- When `brew_mode: true`, show brew panel in layout
- Brew panel sections:
  - Archetype selector (dropdown)
  - Key cards list (with add/remove, present/missing status)
  - Combos list (each combo shows cards + completion status)
  - Theme textarea (500 char limit)
- Panel is collapsible/expandable
- All standard deck operations still work

---

## 6. AI Request Context Building

### Decision: Build Rich Context Object for Each Request

**Rationale:**
- AI needs brew + deck state + user question for quality response
- Structured context enables consistent expert reasoning
- Include deck statistics for informed analysis

**Context Object Structure:**
```elixir
%BrewContext{
  brew: %Brew{
    archetype: :control,
    key_cards: ["Teferi, Hero of Dominaria"],
    combos: [%Combo{cards: [...], description: "..."}],
    theme: "..."
  },
  deck: %DeckSummary{
    format: :modern,
    mainboard_count: 58,
    sideboard_count: 12,
    cards_by_type: %{creature: 12, instant: 16, ...},
    mana_curve: [2, 8, 12, 10, 4, 2],  # by CMC
    color_distribution: %{W: 20, U: 24, ...},
    avg_mana_value: 2.8,
    missing_key_cards: ["Card X"],
    incomplete_combos: [%Combo{...}]
  },
  question: "What cards should I add to improve my control matchup?"
}
```

**Implementation Notes:**
- Build context on each chat request
- Calculate deck stats from current state
- Pass to AnthropicClient with Orchestrator system prompt
- Token budget: ~2000 tokens for context, leaves room for response

---

## 7. Model Selection for Orchestration

### Decision: Configurable Models Per Agent

**Rationale:**
- Phase 2 uses Haiku for fast, cheap command parsing (structured output)
- Brew Mode needs nuanced synthesis of expert perspectives
- Different tasks have different quality/cost requirements
- Users should be able to tune models for their needs
- Future-proofing for new models and providers

**Cost Comparison (Anthropic 2026):**
| Model | Input Cost | Output Cost | Use Case |
|-------|-----------|-------------|----------|
| Haiku | $0.25/1M | $1.25/1M | Command parsing, simple tasks |
| Sonnet | $3/1M | $15/1M | Expert synthesis, complex reasoning |
| Opus | $15/1M | $75/1M | Deep analysis, when quality critical |

**Implementation Notes:**
- Each agent has configurable model selection
- Default configurations:
  - Command Parser: Haiku (fast, cheap)
  - Orchestrator: Sonnet (balanced)
  - Individual Experts: Inherit from Orchestrator or override
- Model abstraction layer handles provider differences
- Consider streaming for longer responses (UX improvement)

---

## 11. Multi-Model Architecture

### Decision: Provider-Agnostic Agent Configuration

**Rationale:**
- Future-proof for new models (GPT-5, Gemini, open source)
- Different tasks may benefit from different models
- Cost optimization per use case
- Allow experimentation without code changes

**Architecture:**
```elixir
%AgentConfig{
  agent_id: "orchestrator",
  name: "Orchestrator",
  description: "Synthesizes expert responses into unified voice",
  provider: "anthropic",           # anthropic | openai | xai | ...
  model: "claude-sonnet-4-20250514",
  system_prompt: "...",            # Editable in UI
  default_prompt: "...",           # Original, for reset
  max_tokens: 1024,
  context_window: 200_000,
  temperature: 0.7,
  enabled: true,
  cost_per_1k_input: 0.003,
  cost_per_1k_output: 0.015,
  updated_at: ~U[2026-01-04 00:00:00Z]
}
```

**Provider Differences:**
| Provider | System Prompt | History Format | Notes |
|----------|--------------|----------------|-------|
| Anthropic (Claude) | Separate `system` param | `messages` array | Prefers system separate |
| OpenAI | `system` role in messages | `messages` array | System as first message |
| xAI (Grok) | Similar to OpenAI | `messages` array | TBD |
| Ollama/Local | Varies by model | `messages` array | Model-specific |

**Implementation Notes:**
- `PromptFormatter` module handles provider-specific formatting
- Each provider has adapter implementing common interface
- System prompt stored separately, formatted at request time
- History truncation respects context window limits

---

## 12. Editable System Prompts

### Decision: Database-Stored Prompts with UI Editor

**Rationale:**
- Rapid iteration without code deploys
- Users can customize agent behavior
- Version history via updated_at
- Easy A/B testing of prompts

**Storage Strategy:**
```sql
CREATE TABLE agent_configs (
  id UUID PRIMARY KEY,
  agent_id VARCHAR(50) UNIQUE NOT NULL,  -- 'orchestrator', 'command_parser', etc.
  name VARCHAR(100) NOT NULL,
  description TEXT,
  provider VARCHAR(50) NOT NULL,
  model VARCHAR(100) NOT NULL,
  system_prompt TEXT NOT NULL,
  default_prompt TEXT NOT NULL,          -- For reset functionality
  max_tokens INTEGER DEFAULT 1024,
  context_window INTEGER DEFAULT 200000,
  temperature DECIMAL(3,2) DEFAULT 0.7,
  enabled BOOLEAN DEFAULT true,
  cost_per_1k_input DECIMAL(10,6),
  cost_per_1k_output DECIMAL(10,6),
  inserted_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

**UI Requirements:**
- List all agents with current model/status
- Edit system prompt with syntax highlighting
- Preview prompt with sample context
- Reset to default button
- Show estimated cost per request

**Implementation Notes:**
- Load configs on app start, cache in ETS
- Invalidate cache on config update
- Admin-only access initially (no auth = everyone)
- Future: per-user prompt overrides

---

## 13. Prompt Formatting Abstraction

### Decision: Provider Adapters with Common Interface

**Rationale:**
- Models have different preferences for system prompt placement
- Some models perform better with system in first message
- Future models may have new conventions
- Clean separation of concerns

**Interface:**
```elixir
defmodule MtgDeckBuilder.AI.ProviderAdapter do
  @callback format_request(system_prompt, messages, options) :: request_body
  @callback parse_response(response) :: {:ok, content} | {:error, reason}
  @callback supports_streaming?() :: boolean
end

# Anthropic adapter
defmodule MtgDeckBuilder.AI.Adapters.Anthropic do
  @behaviour ProviderAdapter

  def format_request(system_prompt, messages, opts) do
    %{
      model: opts[:model],
      system: system_prompt,  # Separate param
      messages: messages,
      max_tokens: opts[:max_tokens]
    }
  end
end

# OpenAI adapter
defmodule MtgDeckBuilder.AI.Adapters.OpenAI do
  @behaviour ProviderAdapter

  def format_request(system_prompt, messages, opts) do
    %{
      model: opts[:model],
      messages: [%{role: "system", content: system_prompt} | messages],
      max_tokens: opts[:max_tokens]
    }
  end
end
```

**Implementation Notes:**
- Adapter selection based on `provider` field in AgentConfig
- Easy to add new providers
- Consistent interface regardless of backend

---

## 8. Format Legality Validator

### Decision: Separate Validation Pass, Not Expert

**Rationale:**
- Format legality is mechanical, not advisory
- Run before/after expert consultation
- Can flag issues proactively (e.g., "BTW, Card X is banned in Modern")
- Not part of conversational response synthesis

**Implementation Notes:**
- Reuse existing format validation from MVP
- Run after deck modifications to flag issues
- Include legality issues in response when relevant
- Add `legality_warnings` to response if cards in brew/deck are illegal

---

## 9. Brew Mode Toggle Behavior

### Decision: Preserve Mode Across Session, Default Off

**Rationale:**
- Users who want brew mode should stay in it
- New users see simple interface by default
- Mode preference stored with deck state

**Implementation Notes:**
- Add `brew_mode: false` to initial deck state
- Toggle button in deck builder header
- On toggle, update assign + persist to localStorage
- Layout conditionally renders brew panel

---

## 10. Error Handling for Expert AI

### Decision: Graceful Degradation with Generic Helpful Response

**Rationale:**
- If AI fails, still show deck stats and basic info
- Don't block user from deck building
- Same pattern as Phase 2 chat errors

**Implementation Notes:**
- Catch API timeout/errors
- Show: "Unable to analyze right now. Here's what I can tell you locally: [deck stats]"
- Log error for debugging
- Suggest user try again or rephrase question

---

## Open Questions (Resolved)

| Question | Resolution |
|----------|------------|
| How do experts interact? | Single Orchestrator prompt contains all expert personas |
| Where does expert "knowledge" live? | In system prompt, stored in DB, editable in UI |
| Brew storage | Extend localStorage deck state |
| Model for synthesis | Configurable per agent (default: Sonnet for Orchestrator, Haiku for commands) |
| Expert selection | Implicit via Claude inference, not explicit routing |
| Different models per agent? | Yes, each agent can have different provider/model |
| System prompt storage | PostgreSQL with UI editor |
| Provider differences | Adapter pattern handles system prompt placement, history format |

---

## References

- [Anthropic Claude System Prompts](https://docs.anthropic.com/claude/docs/system-prompts)
- [Multi-agent patterns](https://www.anthropic.com/research/building-effective-agents)
- Phase 2 AI Chat Commands implementation (existing code)
