# Quickstart: Brew Mode

**Feature:** 3-brew-mode
**Date:** 2026-01-04

## Overview

Brew Mode adds strategic context to decks, enabling multi-expert AI collaboration for intelligent deck building assistance. This document provides integration scenarios and usage examples.

---

## Integration Scenarios

### Scenario 1: Enter Brew Mode and Define Strategy

**Steps:**
1. User clicks "Brew Mode" toggle in deck builder header
2. Brew panel appears alongside existing UI
3. User selects archetype: "Control"
4. User adds key cards: "Teferi, Hero of Dominaria", "Supreme Verdict"
5. User adds theme: "UW Control focusing on planeswalker win conditions"

**Expected Result:**
- Brew panel shows all entered data
- Key cards show present/missing status based on deck contents
- Data persists to localStorage

**Test:**
```javascript
// Check localStorage after setup
const deckState = JSON.parse(localStorage.getItem('mtg_deck_state'))
console.log(deckState.brew)
// {
//   archetype: "control",
//   key_cards: ["Teferi, Hero of Dominaria", "Supreme Verdict"],
//   combos: [],
//   theme: "UW Control focusing on planeswalker win conditions"
// }
```

---

### Scenario 2: Define a Combo

**Steps:**
1. In Brew Mode, click "Add Combo"
2. Search and select: "Splinter Twin"
3. Search and select: "Deceiver Exarch"
4. Enter description: "Infinite tokens on opponent's end step"
5. Save combo

**Expected Result:**
- Combo appears in combos list
- Shows complete/incomplete status based on deck contents
- If both cards in deck: "Complete"
- If missing pieces: "Incomplete (missing: Deceiver Exarch)"

**Test:**
```elixir
# Server-side validation
iex> combo = %Combo{cards: ["Splinter Twin", "Deceiver Exarch"], description: "Infinite tokens"}
iex> Combo.validate(combo)
:ok

iex> invalid = %Combo{cards: ["Only One Card"]}
iex> Combo.validate(invalid)
{:error, :invalid_card_count}
```

---

### Scenario 3: Ask AI for Strategic Advice

**Steps:**
1. In Brew Mode with brew defined
2. Type in chat: "What cards should I add to finish my mainboard?"
3. Wait for AI response

**Expected Result:**
- Loading indicator appears
- AI responds with synthesized expert advice
- Response considers archetype, key cards, combos, theme
- Response is conversational, not a list of expert opinions
- Specific card suggestions included when relevant

**Example Response:**
```
With 58 cards and a solid UW Control shell, you have room for 2 more cards.
Looking at your curve and the planeswalker theme, I'd suggest:

1. **Shark Typhoon** - Incredibly flexible, works as both a threat and a
   cycling cantrip. It synergizes well with your planeswalker strategy.

2. **Castle Ardenvale** - Your land count is good at 24, and replacing a
   Plains with Castle Ardenvale gives you a late-game token generator.
```

---

### Scenario 4: Check Deck Completeness

**Steps:**
1. Define brew with 3 key cards and 1 combo
2. Add 2 of 3 key cards to deck
3. Add 1 of 2 combo pieces to deck
4. View brew panel

**Expected Result:**
- Key cards section shows:
  - "Teferi, Hero of Dominaria" ✓ (2 copies)
  - "Supreme Verdict" ✓ (4 copies)
  - "Cryptic Command" ✗ Missing
- Combos section shows:
  - "Splinter Twin + Deceiver Exarch" - Incomplete (missing: Deceiver Exarch)

---

### Scenario 5: Ask About Missing Cards

**Steps:**
1. Have incomplete brew (missing key cards or combo pieces)
2. Ask: "What am I missing?"

**Expected Result:**
- AI considers brew context
- Points out missing key cards
- Points out incomplete combos
- Suggests whether to add them or alternatives

**Example Response:**
```
Looking at your brew, you're missing:

**Key Card:** Cryptic Command - This is essential for your control strategy
as a flexible answer. At 4 mana, it fits your curve. I'd prioritize finding
room for 2-3 copies.

**Combo Incomplete:** Your Splinter Twin combo is missing Deceiver Exarch.
However, since your brew focuses on planeswalker control, you might consider
whether the combo fits your overall theme, or if you'd rather lean into the
planeswalker plan instead.
```

---

### Scenario 6: Toggle Brew Mode Off

**Steps:**
1. In Brew Mode with data entered
2. Click "Brew Mode" toggle (off)
3. Verify normal layout
4. Toggle back on

**Expected Result:**
- Brew panel disappears
- Normal deck builder layout
- All deck operations still work
- Brew data preserved
- Toggle back on → brew data intact

---

### Scenario 7: Normal Commands in Brew Mode

**Steps:**
1. In Brew Mode
2. Type command: "add 4 lightning bolt"

**Expected Result:**
- Command processed by Phase 2 system (Haiku)
- Card added to deck
- Normal command response
- Brew context NOT used for simple commands

**Distinguishing Factor:**
- Commands (add, remove, set, move, undo) → Phase 2 Haiku
- Questions (what, why, how, suggest, analyze) → Brew Orchestrator Sonnet

---

### Scenario 8: AI Graceful Degradation

**Steps:**
1. In Brew Mode with API unavailable/timeout
2. Ask: "Analyze my deck"

**Expected Result:**
- Loading indicator shows
- Timeout after 30 seconds
- Fallback message appears with local stats:

```
Unable to get AI analysis right now. Here's what I can tell you:

**Deck Status:**
- Mainboard: 58/60 cards
- Sideboard: 12/15 cards
- Avg Mana Value: 2.8

**Brew Progress:**
- Missing Key Cards: Cryptic Command
- Incomplete Combos: 1

Please try again or use the UI to continue building.
```

---

## Quick Reference

### Brew Sections

| Section | Type | Limit | Required |
|---------|------|-------|----------|
| Archetype | enum | 1 selection | No |
| Key Cards | list | 10 max | No |
| Combos | list | 5 max (2-4 cards each) | No |
| Theme | text | 500 chars | No |

### Archetypes

- Control
- Aggro
- Midrange
- Combo
- Tempo
- Ramp

### Question Triggers (Orchestrator)

These phrases route to the multi-expert Orchestrator:

- "What should I..."
- "Suggest..."
- "Analyze..."
- "What am I missing?"
- "How do I improve..."
- "Why is... better than..."
- "What's good against..."

### Command Triggers (Phase 2 Haiku)

These phrases route to simple command parsing:

- "Add..."
- "Remove..."
- "Set..."
- "Move..."
- "Undo"
- "Help"
- "Deck status"

---

## API Usage

### Brew Question Request

```elixir
# Building context
context = BrewContext.build(brew, deck, "What should I add?")

# Sending to Orchestrator
{:ok, response} = Orchestrator.ask(context, format: :modern)

# Response structure
%{
  content: "For your control deck...",
  suggestions: [%{card_name: "Shark Typhoon", reason: "...", action: :add}],
  warnings: ["Consider sideboard for aggro"]
}
```

### Cost Tracking

Brew Mode questions use Sonnet (~$0.009/question) vs Phase 2 commands using Haiku (~$0.00003/command).

Admin dashboard at `/admin/costs` shows breakdown by model.

---

## Testing Checklist

- [ ] Brew Mode toggle works
- [ ] Archetype selection persists
- [ ] Key cards add/remove with validation
- [ ] Card autocomplete works
- [ ] Combos add/edit/remove with validation
- [ ] Theme text area with character limit
- [ ] Present/missing status for key cards
- [ ] Complete/incomplete status for combos
- [ ] Brew questions get Orchestrator response
- [ ] Commands still use Haiku
- [ ] API failure shows fallback stats
- [ ] Data persists across page refresh
- [ ] Brew preserved when toggling mode off/on
