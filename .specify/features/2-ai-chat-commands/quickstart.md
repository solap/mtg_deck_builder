# Quickstart: AI Chat Commands

**Feature:** 2-ai-chat-commands
**Date:** 2026-01-04

## Prerequisites

1. MVP deck builder running (`mix phx.server`)
2. Card database populated (`mix cards.import`)
3. Anthropic API key configured

## Setup

### 1. Configure API Key

Add to `.env.local` (already gitignored):

```bash
ANTHROPIC_API_KEY=sk-ant-api03-your-key-here
```

Load in runtime config:

```elixir
# config/runtime.exs
config :mtg_deck_builder, :anthropic,
  api_key: System.get_env("ANTHROPIC_API_KEY")
```

### 2. Run Migration

```bash
mix ecto.migrate
# Creates api_usage_logs table
```

### 3. Start Server

```bash
mix phx.server
# Navigate to http://localhost:4000
```

---

## Basic Usage

### Adding Cards

```
> add 4 lightning bolt
Added 4x Lightning Bolt to mainboard

> add 2 counterspell to sideboard
Added 2x Counterspell to sideboard
```

### Removing Cards

```
> remove lightning bolt
Removed 4x Lightning Bolt from mainboard

> remove 1 counterspell from sideboard
Removed 1x Counterspell from sideboard
```

### Moving Cards

```
> move 2 lightning bolt to sideboard
Moved 2x Lightning Bolt to sideboard

> move counterspell to mainboard
Moved 2x Counterspell to mainboard
```

### Updating Quantities

```
> set lightning bolt to 3
Updated Lightning Bolt to 3 copies

> add 1 more lightning bolt
Updated Lightning Bolt to 4 copies
```

### Querying Deck

```
> how many lightning bolt
You have 4x Lightning Bolt in mainboard

> show sideboard
Sideboard (5 cards):
- 2x Counterspell
- 3x Negate

> deck status
Mainboard: 52/60 cards
Sideboard: 5/15 cards
Status: Incomplete (need 8 more mainboard cards)
```

### Undo

```
> add 4 brainstorm
Added 4x Brainstorm to mainboard

> undo
Undone: Added 4x Brainstorm to mainboard
```

### Help

```
> help
Available commands:
- add [qty] <card> [to mainboard/sideboard]
- remove [qty] <card> [from mainboard/sideboard]
- move [qty] <card> to mainboard/sideboard
- set <card> to <qty>
- how many <card>
- show mainboard/sideboard
- deck status
- undo
```

---

## Handling Ambiguous Cards

When multiple cards match:

```
> add 4 bolt

Multiple cards match "bolt". Which did you mean?
1. Lightning Bolt (M21)
2. Searing Bolt (TST)
3. Bolt Bend (WAR)

> 1
Added 4x Lightning Bolt to mainboard
```

---

## Error Messages

### Card Not Found

```
> add 4 litning bolt
No card found matching "litning bolt". Did you mean:
- Lightning Bolt
- Lightning Strike
```

### Copy Limit

```
> add 2 lightning bolt
Cannot add 6th copy of Lightning Bolt (max 4 for non-basic lands).
Current count: 4 in mainboard
```

### Format Illegal

```
> add 4 channel
Channel is banned in Modern. Switch to Vintage or Legacy to add this card.
```

### AI Unavailable

```
> add 4 lightning bolt
AI temporarily unavailable, please use UI controls.
```

---

## Admin Dashboard

Access at: `http://localhost:4000/admin/costs`

Shows:
- Total API requests by provider
- Token usage breakdown
- Estimated costs (USD)
- Date range filtering

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `/` | Focus chat input |
| `Enter` | Submit command |
| `↑` / `↓` | Navigate command history |
| `Escape` | Clear input / close disambiguation |

---

## Testing Commands Manually

In IEx:

```elixir
# Parse a command
alias MtgDeckBuilder.Chat.CommandParser

{:ok, parsed} = CommandParser.parse("add 4 lightning bolt")
# => %ParsedCommand{action: :add, card_name: "lightning bolt", quantity: 4, ...}

# Execute against deck
alias MtgDeckBuilder.Chat.CommandExecutor

deck = %Deck{...}
{:ok, new_deck, message} = CommandExecutor.execute(parsed, deck)
```

---

## Troubleshooting

### "AI temporarily unavailable"

1. Check ANTHROPIC_API_KEY is set
2. Verify key is valid at console.anthropic.com
3. Check for rate limiting (429 errors in logs)

### Commands Not Recognized

1. Try simpler phrasing: "add 4 bolt" instead of "put four bolts in"
2. Check card name spelling
3. Use `help` to see supported commands

### Card Not Found

1. Card may not be legal in current format
2. Try full card name instead of abbreviation
3. Check card exists: `Cards.search("card name")` in IEx
