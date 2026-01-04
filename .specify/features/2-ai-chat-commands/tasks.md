# Tasks: AI Chat Commands

**Feature:** 2-ai-chat-commands
**Generated:** 2026-01-04
**Spec Version:** 1.0.0
**Plan Version:** 1.0.0

## Overview

This task list implements AI-powered chat commands for the MTG Deck Builder, enabling natural language deck management.

**User Stories (from spec.md):**
- US1: Add Cards via Chat - Add cards using natural language commands
- US2: Remove Cards via Chat - Remove cards with chat commands
- US3: Update Card Quantity via Chat - Change quantities via commands
- US4: Move Cards Between Boards via Chat - Move cards with commands
- US5: View Deck Status via Chat - Query deck state
- US6: Undo Last Action via Chat - Single-level undo
- US7: View API Costs (Admin) - Admin cost dashboard

**Architecture:**
- Anthropic Claude API for command parsing (tool_use)
- pg_trgm for fuzzy card name matching
- PostgreSQL for API usage logging
- localStorage for chat history persistence

---

## Phase 1: Setup

**Goal:** Configure AI infrastructure, create base modules
**Test:** `mix compile` succeeds, Anthropic API key loads from config
**Dependencies:** MVP complete

- [X] T001 Add ANTHROPIC_API_KEY to config/runtime.exs loading from System.get_env
- [X] T002 [P] Create lib/mtg_deck_builder/ai/ directory structure
- [X] T003 [P] Create lib/mtg_deck_builder/chat/ directory structure
- [X] T004 Create migration priv/repo/migrations/TIMESTAMP_create_api_usage_logs.exs with fields per data-model.md
- [X] T005 Add indexes to migration: provider, inserted_at, (provider, inserted_at) composite
- [X] T006 Run `mix ecto.migrate` to apply api_usage_logs migration
- [X] T007 Create migration priv/repo/migrations/TIMESTAMP_add_pg_trgm.exs to enable pg_trgm extension
- [X] T008 Run `mix ecto.migrate` to apply pg_trgm migration

**Acceptance:** `mix compile` clean, migrations applied, config loads API key

---

## Phase 2: Foundational - AI Client & Data Structures

**Goal:** Anthropic API client works, structs defined, logging functional
**Test:** `AnthropicClient.parse_command("add 4 bolt")` returns ParsedCommand struct
**Dependencies:** Phase 1 complete

- [X] T009 Create lib/mtg_deck_builder/ai/parsed_command.ex struct with fields: action, card_name, quantity, source_board, target_board, query_type, raw_input, confidence
- [X] T010 Add validation functions to ParsedCommand: valid?/1, validate/1
- [X] T011 Create lib/mtg_deck_builder/ai/api_usage_log.ex Ecto schema matching data-model.md
- [X] T012 Create lib/mtg_deck_builder/ai/api_logger.ex with log_request/1 function
- [X] T013 Create lib/mtg_deck_builder/ai/anthropic_client.ex module with @moduledoc
- [X] T014 Implement AnthropicClient.parse_command/1 with Tesla HTTP POST to Anthropic Messages API
- [X] T015 Define tool_use schema for deck_command in AnthropicClient per contracts/api.md
- [X] T016 Implement AnthropicClient response parsing to extract tool_use input as ParsedCommand
- [X] T017 Implement AnthropicClient error handling for 400, 401, 429, 500, 529 responses
- [X] T018 Integrate ApiLogger.log_request/1 call after each Anthropic API call in AnthropicClient
- [X] T019 [P] Create test/mtg_deck_builder/ai/parsed_command_test.exs with validation tests
- [X] T020 [P] Create test/mtg_deck_builder/ai/anthropic_client_test.exs with mocked API responses

**Acceptance:**
```elixir
iex> AnthropicClient.parse_command("add 4 lightning bolt")
{:ok, %ParsedCommand{action: :add, card_name: "lightning bolt", quantity: 4}}

iex> Repo.aggregate(ApiUsageLog, :count)
1
```

---

## Phase 3: US1 - Add Cards via Chat

**Goal:** User can add cards to deck using chat command
**Test:** Type "add 4 lightning bolt", card appears in mainboard
**Dependencies:** Phase 2 complete

- [X] T021 [US1] Create lib/mtg_deck_builder/chat/card_resolver.ex module
- [X] T022 [US1] Implement CardResolver.resolve/2 using pg_trgm similarity query on cards table
- [X] T023 [US1] Implement CardResolver.suggest/2 returning top 5 similar card names
- [X] T024 [US1] Add similarity threshold logic: >0.8 auto-match, 0.3-0.8 disambiguation, <0.3 no match
- [X] T025 [US1] Create ETS table :recent_card_selections in application.ex supervision tree
- [X] T026 [US1] Implement CardResolver.remember_selection/2 and get_recent/1 using ETS
- [X] T027 [US1] Create lib/mtg_deck_builder/chat/command_executor.ex module
- [X] T028 [US1] Implement CommandExecutor.execute/2 dispatch function for all action types
- [X] T029 [US1] Implement execute_add/3 in CommandExecutor calling Decks.add_card
- [X] T030 [US1] Add validation in execute_add: 4-copy max, format legality, sideboard 15 max
- [X] T031 [US1] Create lib/mtg_deck_builder/chat/response_formatter.ex module
- [X] T032 [US1] Implement ResponseFormatter.format_success/2 for add action: "Added Nx CardName to board"
- [X] T033 [US1] Implement ResponseFormatter.format_error/2 with user-friendly messages per error codes

**Acceptance:** `CommandExecutor.execute(%ParsedCommand{action: :add, card_name: "lightning bolt", quantity: 4}, deck)` adds card and returns success message

---

## Phase 4: US2 - Remove Cards via Chat

**Goal:** User can remove cards from deck using chat command
**Test:** Type "remove 2 lightning bolt", quantity decreases or card removed
**Dependencies:** Phase 3 complete (shares CommandExecutor)

- [X] T034 [US2] Implement execute_remove/3 in CommandExecutor
- [X] T035 [US2] Handle remove all copies when no quantity specified in execute_remove
- [X] T036 [US2] Handle remove specific quantity with auto-remove at 0 in execute_remove
- [X] T037 [US2] Add error handling for card not in deck in execute_remove
- [X] T038 [US2] Add ResponseFormatter.format_success/2 for remove action: "Removed Nx CardName from board"

**Acceptance:** Remove command decreases quantity or removes card entirely

---

## Phase 5: US3 - Update Card Quantity via Chat

**Goal:** User can set card quantity directly
**Test:** Type "set lightning bolt to 3", quantity changes to 3
**Dependencies:** Phase 4 complete

- [X] T039 [US3] Implement execute_set/3 in CommandExecutor
- [X] T040 [US3] Validate quantity range 1-4 (except basic lands) in execute_set
- [X] T041 [US3] Handle "add N more" incremental syntax in AnthropicClient tool schema
- [X] T042 [US3] Add ResponseFormatter.format_success/2 for set action: "Updated CardName to N copies"

**Acceptance:** Set command changes quantity directly

---

## Phase 6: US4 - Move Cards Between Boards via Chat

**Goal:** User can move cards between mainboard and sideboard
**Test:** Type "move 2 lightning bolt to sideboard", cards move
**Dependencies:** Phase 5 complete

- [X] T043 [US4] Implement execute_move/3 in CommandExecutor
- [X] T044 [US4] Handle move all copies when no quantity specified in execute_move
- [X] T045 [US4] Validate source board has the card in execute_move
- [X] T046 [US4] Validate target board constraints (sideboard 15 max) in execute_move
- [X] T047 [US4] Add ResponseFormatter.format_success/2 for move action: "Moved Nx CardName to board"

**Acceptance:** Move command transfers cards between boards

---

## Phase 7: US5 - View Deck Status via Chat

**Goal:** User can query deck state via chat
**Test:** Type "deck status", see card counts and validity
**Dependencies:** Phase 6 complete

- [X] T048 [US5] Implement execute_query/3 in CommandExecutor
- [X] T049 [US5] Handle query_type :count - return card count in each board
- [X] T050 [US5] Handle query_type :list - return formatted card list for board
- [X] T051 [US5] Handle query_type :status - return deck summary with validity
- [X] T052 [US5] Add ResponseFormatter.format_query_result/2 with formatted output

**Acceptance:** Query commands return formatted deck information

---

## Phase 8: US6 - Undo Last Action via Chat

**Goal:** User can undo last chat-initiated action
**Test:** Add card, type "undo", card removed
**Dependencies:** Phase 7 complete

- [X] T053 [US6] Create lib/mtg_deck_builder/chat/undo_server.ex GenServer
- [X] T054 [US6] Implement UndoServer.start_link/1 and init/1 with empty state
- [X] T055 [US6] Implement UndoServer.save_state/2 storing {previous_deck, action_description}
- [X] T056 [US6] Implement UndoServer.undo/0 returning previous deck and clearing state
- [X] T057 [US6] Implement UndoServer.clear/0 to reset undo state
- [X] T058 [US6] Add UndoServer to application.ex supervision tree
- [X] T059 [US6] Update CommandExecutor to call UndoServer.save_state before modifications
- [X] T060 [US6] Implement execute_undo/2 in CommandExecutor calling UndoServer.undo
- [X] T061 [US6] Add ResponseFormatter.format_success/2 for undo: "Undone: action_description"
- [X] T062 [US6] Handle "nothing to undo" error in execute_undo

**Acceptance:** Undo command restores previous deck state

---

## Phase 9: Chat UI & LiveView Integration

**Goal:** Chat interface in UI, all commands work end-to-end
**Test:** Type commands in browser, see responses, deck updates
**Dependencies:** Phases 3-8 complete

- [X] T063 Update lib/mtg_deck_builder_web/live/deck_live.ex with chat assigns: messages, chat_input, processing, disambiguation_options
- [X] T064 Create lib/mtg_deck_builder_web/components/chat_component.ex function component
- [X] T065 Implement chat_component with message list and input field
- [X] T066 Add chat_component to lib/mtg_deck_builder_web/live/deck_live.html.heex layout
- [X] T067 Implement handle_event("submit_command", %{"command" => cmd}, socket) in deck_live.ex
- [X] T068 Wire submit_command to AnthropicClient.parse_command -> CardResolver.resolve -> CommandExecutor.execute pipeline
- [X] T069 Implement handle_event("select_card", %{"selection_index" => idx}, socket) for disambiguation
- [X] T070 Push command_result/command_error events to client after execution
- [X] T071 Create assets/js/hooks/chat_input.js with keyboard handling
- [X] T072 Implement up/down arrow history navigation in chat_input.js
- [X] T073 Implement Escape key to clear input in chat_input.js
- [X] T074 Implement "/" keyboard shortcut to focus chat input in deck_live.ex
- [X] T075 Register ChatInput hook in assets/js/app.js
- [X] T076 [P] Extend assets/js/hooks/deck_storage.js to persist chat messages
- [X] T077 [P] Implement handleEvent("sync_chat", {messages}) in deck_storage.js
- [X] T078 Push sync_chat event after each message in deck_live.ex
- [X] T079 Load chat history from localStorage on mount in deck_live.ex via handle_event("load_chat")
- [X] T080 Add loading indicator UI during AI processing (show when processing=true)
- [X] T081 Create disambiguation UI component showing numbered card options
- [X] T082 Implement help command response with available commands list

**Acceptance:** Full end-to-end chat functionality in browser

---

## Phase 10: US7 - Admin Cost Dashboard

**Goal:** Admin can view API usage costs at /admin/costs
**Test:** Visit /admin/costs, see cost breakdown by provider
**Dependencies:** Phase 2 complete (ApiUsageLog exists)

- [X] T083 [US7] Create lib/mtg_deck_builder/ai/cost_stats.ex module
- [X] T084 [US7] Implement CostStats.totals/1 returning aggregate stats for date range
- [X] T085 [US7] Implement CostStats.by_provider/1 returning stats grouped by provider
- [X] T086 [US7] Implement CostStats.by_day/1 returning daily breakdown
- [X] T087 [US7] Create lib/mtg_deck_builder_web/live/admin/costs_live.ex LiveView
- [X] T088 [US7] Add assigns: from_date, to_date, provider_filter, stats
- [X] T089 [US7] Create lib/mtg_deck_builder_web/live/admin/costs_live.html.heex template
- [X] T090 [US7] Display totals: requests, input_tokens, output_tokens, cost_cents
- [X] T091 [US7] Display provider breakdown table
- [X] T092 [US7] Display daily breakdown chart/table
- [X] T093 [US7] Implement date range filter UI with handle_event("filter")
- [X] T094 [US7] Implement provider filter dropdown
- [X] T095 [US7] Add route "/admin/costs" to lib/mtg_deck_builder_web/router.ex

**Acceptance:** Visit /admin/costs, see costs broken down by provider with filtering

---

## Phase 11: Polish & Error Handling

**Goal:** Graceful degradation, edge cases handled, code quality
**Test:** API failure shows friendly error, credo/dialyzer pass
**Dependencies:** All previous phases complete

- [X] T096 Add API failure handling in deck_live.ex: catch errors, show "AI temporarily unavailable" message
- [X] T097 Implement timeout handling (10s max) in AnthropicClient
- [X] T098 Add graceful fallback message suggesting UI controls on API error
- [X] T099 Handle edge case: empty card name in command
- [X] T100 Handle edge case: invalid quantity (negative, > 15)
- [X] T101 Handle edge case: card not legal in current format
- [X] T102 Handle edge case: restricted card in Vintage (1-copy max)
- [X] T103 Add comprehensive error messages per error codes in contracts/api.md
- [X] T104 Run `mix credo --strict` and fix all warnings
- [X] T105 Run `mix dialyzer` and fix all type issues
- [X] T106 Verify chat works in Chrome, Firefox, Safari, Edge
- [X] T107 Update README.md with chat command examples

**Acceptance:** All edge cases handled gracefully, code quality passes

---

## Dependencies Graph

```
Phase 1 (Setup)
    ↓
Phase 2 (Foundational: AI Client)
    ↓
    ├── Phase 3 (US1: Add Cards) → Phase 4 (US2: Remove) → Phase 5 (US3: Update)
    │                                                              ↓
    │                                                      Phase 6 (US4: Move)
    │                                                              ↓
    │                                                      Phase 7 (US5: Query)
    │                                                              ↓
    │                                                      Phase 8 (US6: Undo)
    │                                                              ↓
    └── Phase 10 (US7: Admin Dashboard) ←────────────────── Phase 9 (Chat UI)
                                                                   ↓
                                                          Phase 11 (Polish)
```

## Parallel Execution Opportunities

**Within Phase 1:**
- T002, T003 (directory creation) can run parallel
- T004-T006, T007-T008 (migrations) must be sequential

**Within Phase 2:**
- T019, T020 (tests) can run parallel after implementation

**Across Phases:**
- Phase 10 (Admin Dashboard) can start after Phase 2, parallel with Phases 3-9

## Implementation Strategy

1. **MVP Scope:** Phases 1-4 (Setup + AI Client + Add + Remove) = core chat functionality
2. **First Milestone:** Parse "add 4 lightning bolt", execute command, update deck
3. **Incremental Delivery:** Each user story phase is independently testable
4. **Risk Mitigation:** AI Client (Phase 2) is highest risk - test API mocking thoroughly

---

## Summary

| Metric | Value |
|--------|-------|
| **Total Tasks** | 107 |
| **Setup Tasks** | 8 |
| **Foundational Tasks** | 12 |
| **US1 (Add Cards)** | 13 |
| **US2 (Remove Cards)** | 5 |
| **US3 (Update Quantity)** | 4 |
| **US4 (Move Cards)** | 5 |
| **US5 (View Status)** | 5 |
| **US6 (Undo)** | 10 |
| **Chat UI Tasks** | 20 |
| **US7 (Admin Dashboard)** | 13 |
| **Polish Tasks** | 12 |
| **Parallel Opportunities** | 8+ tasks marked [P] |

**Suggested First Milestone:** Complete Phases 1-4 (38 tasks) for basic add/remove chat functionality.
