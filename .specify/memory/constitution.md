<!--
Sync Impact Report
==================
Version change: n/a → 1.0.0
Added principles:
  - Incremental Delivery First
  - AI-Native Architecture
  - Boring Technology
  - Working Code Over Perfect Code
Added sections: All (initial creation)
Removed sections: None
Templates requiring updates: n/a (initial setup)
Follow-up TODOs: None
-->

# Project Constitution

**Project Name:** MTG Deck Builder
**Version:** 1.0.0
**Ratification Date:** 2026-01-03
**Last Amended:** 2026-01-03

## Purpose

An AI-powered Magic: The Gathering deck builder that leverages multi-agent AI for
intelligent deck building, card recommendations, and strategic analysis. Built with
Elixir/Phoenix LiveView for a real-time hybrid interface (chat for building, visual
for reviewing/editing).

## Core Principles

### Principle 1: Incremental Delivery First

Every change MUST be small, working, and deployable. Features MUST be broken into the
smallest viable increments that can be independently tested and merged.

- Each pull request MUST leave the application in a working state
- Each increment MUST have a clear test criterion before implementation begins
- Database migrations MUST be reversible
- Feature flags SHOULD be used for incomplete features spanning multiple PRs
- Rollback capability is non-negotiable; every commit MUST be revertible without data loss

**Rationale:** The project is structured in testable increments (Setup → Scryfall →
Card UI → Deck CRUD → etc.). Each increment must be verified working before proceeding
to maintain velocity and enable course correction.

### Principle 2: AI-Native Architecture

The application is built around AI as a first-class citizen, not an afterthought.
Multi-agent analysis and AI-assisted building are core features, not add-ons.

- AI service interfaces MUST support multiple providers (Anthropic, OpenAI, Google)
- Agent selection MUST be configurable per task type (cheap/fast vs complex reasoning)
- AI responses MUST be streamable for responsive UX
- Card context MUST be pre-filtered before sending to AI (25,000+ cards cannot fit context)
- Agent results MUST include scores, issues, and specific card recommendations
- Users MUST approve AI suggestions; agents advise, humans decide

**Rationale:** The unique value of this deck builder is intelligent AI analysis. The
architecture must support parallel multi-agent execution, cost-effective model routing,
and user control over AI-suggested changes.

### Principle 3: Boring Technology

Prefer standard Phoenix/LiveView patterns over custom solutions. The application MUST
prioritize reliability over optimization or novelty.

- Use Phoenix generators and conventions as the default starting point
- External APIs (Scryfall) MUST be cached with TTL to respect rate limits
- Third-party dependencies MUST be well-maintained and widely adopted
- Custom abstractions require explicit justification
- Avoid premature optimization; measure before optimizing

**Rationale:** Boring technology has known failure modes, abundant documentation, and
predictable behavior. Phoenix LiveView handles real-time UI updates out of the box,
eliminating the need for custom WebSocket handling.

### Principle 4: Working Code Over Perfect Code

Ship functional features before polishing. Refactor when pain is real, not theoretical.

- "Good enough" is acceptable for initial implementations
- Technical debt is documented, not ignored, but not immediately addressed
- Tests MUST cover critical paths; exhaustive coverage is not required initially
- Integration tests are preferred over unit tests for feature verification
- Anonymous/session-based storage is acceptable before authentication is needed

**Rationale:** A deck builder needs usable features to validate the AI approach.
Perfectionism delays feedback and learning. Real usage reveals what needs refinement.

## Governance

### Amendment Procedure

1. Any contributor MAY propose a constitution amendment
2. Amendments are versioned semantically:
   - MAJOR: Principle removal or fundamental redefinition
   - MINOR: New principle or significant expansion
   - PATCH: Clarifications and wording improvements

### Compliance Review

- Constitution principles guide code review decisions
- Violations SHOULD be flagged in PR reviews with principle reference
- Repeated violations warrant discussion, not punishment

### Version History

| Version | Date       | Summary                        |
|---------|------------|--------------------------------|
| 1.0.0   | 2026-01-03 | Initial constitution ratified  |
