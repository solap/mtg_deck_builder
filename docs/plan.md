# AI-Powered MTG Deck Builder

## Overview
A Magic: The Gathering deck builder that leverages AI for intelligent deck building, card recommendations, and strategic analysis. Built with Elixir/Phoenix LiveView for a real-time hybrid interface (chat for building, visual for reviewing/editing).

## Core Concept
Users can either:
1. **Chat with AI** - "Build me a blue/black control deck for Modern under $200"
2. **Browse/build visually** - Traditional deck builder with AI-powered suggestions
3. **Get deck critique** - Paste an existing deck, get strategic feedback

## Tech Stack
- **Backend**: Elixir + Phoenix (based on your elixir-project-template)
- **Frontend**: Phoenix LiveView (real-time, minimal JS)
- **Database**: PostgreSQL (decks, cached card data)
- **HTTP Client**: Tesla (per your template pattern)
- **JSON**: Jason
- **Card Data**: Scryfall API (free, comprehensive)
- **AI**: Claude API via Anthropic SDK
- **Quality Tools**: Credo, Dialyxir, Doctor, Sobelow, ExCoveralls

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Phoenix LiveView                    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │  Chat View  │  │ Deck Editor │  │ Card Browser│ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────────┐
│                   Core Services                      │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ AI Service  │  │Card Service │  │Deck Service │ │
│  │ (Claude)    │  │ (Scryfall)  │  │ (CRUD+Valid)│ │
│  └─────────────┘  └─────────────┘  └─────────────┘ │
└─────────────────────────────────────────────────────┘
                         │
┌─────────────────────────────────────────────────────┐
│                    PostgreSQL                        │
│  decks | cards_cache | users | chat_history         │
└─────────────────────────────────────────────────────┘
```

## Card Data Import Architecture

### The Problem

Importing ~36,000 cards from Scryfall's 166MB JSON file into PostgreSQL on a memory-constrained Fly.io instance presented several challenges:

1. **Memory pressure**: Loading 166MB JSON into memory causes OOM on 2GB VMs
2. **Connection timeouts**: Long-running INSERT transactions exhaust the connection pool
3. **Slow imports**: Individual INSERTs take minutes, making daily syncs impractical

### The Solution: PostgreSQL COPY Protocol

We use PostgreSQL's COPY protocol via Postgrex, which is 10-100x faster than INSERT:

```
Scryfall API
    ↓ GET bulk-data (find oracle_cards URL)
https://data.scryfall.io/oracle-cards/oracle-cards-YYYYMMDD.json (166MB)
    ↓ hackney streaming download
/tmp/scryfall_oracle_cards_TIMESTAMP.json
    ↓ Jaxon streaming JSON parse (no full load)
Stream of card objects
    ↓ Transform to CSV rows
    ↓ Postgrex.stream() with COPY FROM STDIN
PostgreSQL cards table
```

### Why COPY is Faster

| Factor | INSERT | COPY |
|--------|--------|------|
| SQL parsing | Per row | None |
| Transaction overhead | High | Minimal |
| WAL writes | Per row | Batched |
| Round trips | Per batch | Single stream |
| Index updates | Continuous | Deferred |

**Result**: 36,264 cards in ~11 seconds vs several minutes with batch INSERT.

### Key Implementation Details

```elixir
# CopyImporter uses a dedicated connection (not from pool)
config = Repo.config() |> Keyword.delete(:pool)
{:ok, conn} = Postgrex.start_link(config)

# Stream JSON → CSV → COPY in a single transaction
Postgrex.transaction(conn, fn conn ->
  copy_stream = Postgrex.stream(conn, "COPY cards (...) FROM STDIN WITH CSV", [])

  file_path
  |> File.stream!([], 65_536)           # Stream file in 64KB chunks
  |> Jaxon.Stream.from_enumerable()      # Parse JSON as stream
  |> Jaxon.Stream.query([:root, :all])   # Extract array elements
  |> Stream.map(&card_to_csv_row/1)      # Transform to CSV
  |> Enum.into(copy_stream)              # Pipe to COPY
end, timeout: :infinity)
```

### Automatic Sync Schedule

The `CardSyncWorker` GenServer handles synchronization:

- **First boot (empty DB)**: Schedules import after 30s delay
- **With existing cards**: Schedules daily sync (24h interval)
- **On sync completion**: Schedules next sync
- **On failure**: Retries in 1 hour

### Lessons Learned

1. **Don't use the Ecto pool for bulk operations** - use a dedicated Postgrex connection
2. **Streaming JSON is essential** - Jaxon vs Jason makes the difference between OOM and success
3. **COPY requires CSV format** - transform JSON to CSV rows with proper escaping
4. **PostgreSQL arrays need special format** - `{item1,item2}` not `["item1","item2"]`
5. **Transaction timeout: :infinity** - bulk operations need unlimited time

## Features

### Phase 1: Foundation (MVP)
1. **Scryfall Integration**
   - Card search by name, text, type, colors, CMC
   - Card data caching (respect rate limits)
   - Image fetching (hotlink Scryfall CDN)

2. **Card Display UI**
   - Card preview with image, mana cost, type, text
   - Hover/click for full card details
   - Stats display: CMC, colors, type, legalities, price
   - Card tags (removal, ramp, draw, etc.)

3. **Deck Builder UI (Manual + Chat)**
   - **Manual editing:**
     - Search cards, click to add to deck
     - +/- buttons for quantity
     - Drag to reorder/organize
     - Section organization (creatures, spells, lands, sideboard)
   - **Chat assistance:**
     - "Add 3 more removal spells"
     - "Replace my expensive cards with budget options"
     - AI suggestions appear, user approves/rejects
   - Deck list view with card images + text
   - Format selection (Commander, Standard, Modern, etc.)

4. **Format Validation**
   - Card legality checking
   - Deck size requirements
   - Commander-specific rules (color identity, singleton)

5. **AI Chat Integration**
   - Natural language deck requests
   - "Build me a deck" → AI generates list
   - Stream AI responses via LiveView

### Phase 2: Smart Features
6. **Multi-Agent Deck Analysis**
   - Run specialized AI agents in parallel (see AI Strategy section)
   - Unified analysis dashboard showing scores per category
   - Drill-down into each agent's findings
   - Visual indicators: mana curve chart, color pie, type breakdown

7. **Real-time AI Suggestions**
   - As you add cards, agents provide contextual feedback
   - "You added a 6-drop but only have 33 lands" (Mana Agent)
   - "This card anti-synergizes with your commander" (Synergy Agent)
   - Inline card recommendations while building

8. **Import/Export**
   - Standard deck list formats
   - Import from other sites
   - Export for paper/MTGO/Arena

### Phase 3: Advanced AI
9. **Meta Awareness**
   - Track popular decks/cards
   - "How does my deck fare against the meta?"
   - Sideboard suggestions

10. **Combo Finder**
    - Detect combos in user's deck
    - Suggest combo pieces

11. **Budget Optimizer**
    - "Make this deck cost $X less"
    - Intelligent substitutions

## AI Strategy

### Challenge: Context Window
MTG has 25,000+ unique cards. Can't send all to AI.

### Solution: Structured Retrieval
1. **Pre-filter cards** by format legality, colors, budget
2. **Use Scryfall's search** to find relevant cards based on AI intent
3. **Send curated card lists** to AI for final selection
4. **Cache common queries** (staples by format, popular commanders)

### Multi-Agent Analysis System (Competitive Focus)
Specialized agents focused on making decks more competitive:

| Agent | Focus | Competitive Value |
|-------|-------|-------------------|
| **Legality** | Format rules | Baseline requirement |
| **Mana Base** | Lands, ramp, fixing | Consistent execution |
| **Win Conditions** | Victory paths, speed | Clear plan to win |
| **Synergy** | Card interactions | Multiplicative power |
| **Interaction** | Removal, counters | Disrupt opponents |
| **Consistency** | Tutors, redundancy | Find key pieces |
| **Protection** | Counters, hexproof | Keep engine running |
| **Tempo** | Speed, curve, pressure | Race opponents |
| **Meta Matchup** | Popular decks | Know your weaknesses |

**Agent Architecture:**
```elixir
defmodule MtgDeckBuilder.AI.Agents do
  # Each agent has a focused system prompt
  def analyze(deck, :mana_base) do
    prompt = """
    You are a mana base specialist. Analyze this deck for:
    1. Land count vs curve (recommend 37-40 for Commander)
    2. Color sources vs color requirements
    3. Ramp package (target 10+ pieces)
    4. Mana curve distribution
    5. Color fixing quality

    Provide specific recommendations with card suggestions.
    """
    run_agent(deck, prompt)
  end

  def analyze(deck, :win_conditions) do
    prompt = """
    You are a win condition analyst. Evaluate:
    1. Primary win condition - what's the main path to victory?
    2. Backup plans - if plan A fails, what's plan B?
    3. Speed - what turn can this deck threaten a win?
    4. Resilience - how does it recover from disruption?
    5. Combo potential - any infinite or game-ending combos?

    Suggest improvements to strengthen victory paths.
    """
    run_agent(deck, prompt)
  end

  # ... similar for other agents
end
```

**Parallel Analysis:**
Run all agents concurrently with `Task.async_stream/3`, aggregate results into unified report.

**Scoring System:**
Each agent returns:
- Score (1-10) for their domain
- List of issues found
- Specific card recommendations
- Priority level (critical/warning/suggestion)

### Agent Re-Run Strategy

**Problem:** "Run until all agents agree" causes infinite loops and high costs.

**Solution:** Change-driven + convergence detection + user control.

**1. Tiered Analysis:**
| Tier | Trigger | What Runs | Cost |
|------|---------|-----------|------|
| Instant | Every change | Legality check (local, no AI) | Free |
| Quick | Every change | Mana stats, curve (local math) | Free |
| Targeted | Card change | Only affected agents | Low |
| Full | User clicks "Analyze" | All agents in parallel | Medium |
| Deep | User clicks "Optimize" | Iterative with suggestions | High |

**2. Change → Agent Mapping:**
```elixir
# Only re-run agents affected by the change
def affected_agents(card_type) do
  %{
    land: [:mana_base],
    ramp: [:mana_base, :tempo],
    removal: [:interaction, :tempo],
    creature: [:win_conditions, :synergy, :tempo],
    tutor: [:consistency, :synergy],
    protection: [:protection],
    combo_piece: [:win_conditions, :synergy]
  }[card_type] || [:synergy]
end
```

**3. Convergence Detection:**
```elixir
def analyze_until_stable(deck, max_iterations \\ 3) do
  case iterate(deck, iteration: 0, max: max_iterations) do
    {:stable, issues} ->
      # No critical issues remain
      {:ok, issues}

    {:trade_off, issues, conflicts} ->
      # Agents disagree (e.g., "more removal" vs "more creatures")
      # Present to user for decision
      {:needs_decision, issues, conflicts}

    {:max_iterations, issues} ->
      # Couldn't converge, show current state
      {:ok, issues}
  end
end
```

**4. Issue Priority Levels:**
| Level | Behavior | Example |
|-------|----------|---------|
| Critical | Must fix | Illegal card, severely low land count |
| Warning | Should address | Only 5 removal spells |
| Suggestion | Optional | "Consider Cyclonic Rift" |
| Trade-off | User decides | "More removal = fewer creatures" |

**5. User Controls Changes:**
- Agents suggest, users approve/reject
- "Auto-fix" button for safe suggestions (add lands)
- "Ignore" to dismiss warnings
- Trade-off resolution: user picks priority

## Data Models

```elixir
# Deck
%Deck{
  id: uuid,
  name: string,
  format: enum(:commander, :standard, :modern, ...),
  commander_id: string (nullable),
  cards: [%DeckCard{card_id, quantity, board: :main/:side}],
  user_id: uuid,
  is_public: boolean
}

# CachedCard (from Scryfall)
%CachedCard{
  scryfall_id: string,
  name: string,
  mana_cost: string,
  cmc: float,
  colors: [string],
  color_identity: [string],
  type_line: string,
  oracle_text: string,
  legalities: map,
  prices: map,
  image_uris: map,
  updated_at: datetime
}
```

## File Structure

```
mtg_deck_builder/
├── lib/
│   ├── mtg_deck_builder/
│   │   ├── decks/           # Deck context (CRUD, validation)
│   │   ├── cards/           # Card context (Scryfall client, cache)
│   │   ├── ai/              # AI service (Claude client, prompts)
│   │   └── formats/         # Format rules and validation
│   └── mtg_deck_builder_web/
│       ├── live/
│       │   ├── deck_live/   # Deck editor LiveView
│       │   ├── chat_live/   # AI chat LiveView
│       │   └── search_live/ # Card search LiveView
│       └── components/      # Reusable UI components
├── priv/
│   └── repo/migrations/
└── test/
```

## Implementation Steps (Incremental + Testable)

Each increment is independently testable before moving on.

### Increment 1: Project Setup
**Test:** Phoenix app runs, connects to DB
- [ ] Create project from elixir-project-template
- [ ] Configure PostgreSQL database
- [ ] Set up environment variables (multiple AI keys)
- [ ] Set up Tailwind CSS
- [ ] Create CLAUDE.md with project conventions

### Increment 2: Scryfall Client
**Test:** Can search cards, see JSON response
- [ ] Create Tesla-based HTTP client for Scryfall API
- [ ] Implement card search (name, text, colors, type, CMC)
- [ ] Set up card caching in PostgreSQL with TTL
- [ ] Handle rate limiting (50-100ms between requests)
- [ ] Write tests for search functionality

### Increment 3: Card Display UI
**Test:** Search for card, see image + stats displayed
- [ ] Card search LiveView component
- [ ] Card preview component (image, mana cost, type, text)
- [ ] Card detail modal (full stats, legalities, price)

### Increment 4: Basic Deck CRUD
**Test:** Create deck, save it, reload page, deck persists
- [ ] Deck schema and migrations
- [ ] Deck context with CRUD operations
- [ ] Deck list page (my decks)
- [ ] Create/rename/delete deck

### Increment 5: Deck Editor UI
**Test:** Add cards to deck, see them in list, adjust quantities
- [ ] Deck editor LiveView
- [ ] Add card from search results
- [ ] Remove card / adjust quantity
- [ ] Organize by type (creatures, spells, lands)
- [ ] Session-based storage (no auth yet)

### Increment 6: Local Analysis (No AI)
**Test:** See mana curve chart, color pie, basic stats
- [ ] Mana curve visualization
- [ ] Color distribution chart
- [ ] Card type breakdown
- [ ] Average CMC calculation
- [ ] Format legality checker (rules-based, no AI)

### Increment 7: Multi-Provider AI Client
**Test:** Can call Claude, OpenAI, Gemini with same interface
- [ ] Create unified AI client behaviour
- [ ] Implement Anthropic adapter (Claude models)
- [ ] Implement OpenAI adapter (GPT models)
- [ ] Implement Google adapter (Gemini models)
- [ ] Config-based model selection per task
- [ ] Write tests with mocked responses

### Increment 8: AI Chat
**Test:** Chat says "build me a goblin deck", get card suggestions
- [ ] Chat LiveView with message history
- [ ] Streaming responses
- [ ] Parse card names from AI response
- [ ] Link suggestions to Scryfall data
- [ ] "Add to deck" from suggestions

### Increment 9: First Agent - Mana Base
**Test:** Analyze deck, see mana recommendations
- [ ] Agent behaviour module (common interface)
- [ ] Mana Base agent with focused prompt
- [ ] Display agent results in dashboard
- [ ] Configurable model (start with Haiku)

### Increment 10: Second Agent - Win Conditions
**Test:** Analyze deck, see win condition analysis
- [ ] Win Condition agent
- [ ] Aggregate multiple agent results
- [ ] Parallel execution with Task.async_stream

### Increment 11+: Remaining Agents (one at a time)
Each agent is a separate increment:
- [ ] Synergy Agent (use Opus for complex reasoning)
- [ ] Interaction Agent
- [ ] Consistency Agent
- [ ] Protection Agent
- [ ] Tempo Agent
- [ ] Meta Matchup Agent

### Increment N: Re-Run Infrastructure
**Test:** Add card, see only affected agents re-run
- [ ] Change detector (card type → affected agents)
- [ ] Tiered analysis system
- [ ] Convergence detection
- [ ] Issue priority UI

### Final: Polish
- [ ] Import/export deck lists
- [ ] User authentication
- [ ] Deploy to Fly.io

## Multi-Model Configuration

Support multiple AI providers, choose best model per task:

```elixir
# config/runtime.exs
config :mtg_deck_builder, :ai_providers,
  anthropic: [
    api_key: System.get_env("ANTHROPIC_API_KEY"),
    models: %{
      opus: "claude-opus-4-5-20251101",
      sonnet: "claude-sonnet-4-20250514",
      haiku: "claude-3-5-haiku-20241022"
    }
  ],
  openai: [
    api_key: System.get_env("OPENAI_API_KEY"),
    models: %{
      gpt4o: "gpt-4o",
      gpt4o_mini: "gpt-4o-mini"
    }
  ],
  google: [
    api_key: System.get_env("GOOGLE_API_KEY"),
    models: %{
      gemini_pro: "gemini-pro",
      gemini_flash: "gemini-flash"
    }
  ]

# Default model assignments (easily tweakable)
config :mtg_deck_builder, :agent_models,
  # Chat
  deck_chat: {:anthropic, :sonnet},

  # Agents - start cheap, upgrade if needed
  mana_base: {:anthropic, :haiku},
  win_conditions: {:anthropic, :sonnet},
  synergy: {:anthropic, :opus},        # Complex reasoning
  interaction: {:anthropic, :haiku},
  consistency: {:anthropic, :haiku},
  protection: {:anthropic, :haiku},
  tempo: {:anthropic, :sonnet},
  meta_matchup: {:openai, :gpt4o}      # Try different provider
```

**Model Selection Rationale:**
| Task | Model | Why |
|------|-------|-----|
| Simple analysis | Haiku | Fast (< 1s), cheap, good enough |
| Card suggestions | Sonnet | Better reasoning, still fast |
| Complex synergy | Opus | Needs deep MTG understanding |
| Meta analysis | GPT-4o | Experiment with different perspective |

## Decisions Made

1. **Project Name**: `mtg_deck_builder`
2. **Authentication**: Anonymous first (session-based deck storage), add auth later
3. **MVP AI Scope**: Full chat + inline suggestions from the start
4. **Card images**: Hotlink from Scryfall (their CDN is fast, saves storage)
5. **AI models**: Multi-provider support, configurable per agent
6. **Incremental build**: Each step testable before moving on

## Resources

- [Scryfall API Docs](https://scryfall.com/docs/api)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view)
- [Claude API](https://docs.anthropic.com/claude/reference)
