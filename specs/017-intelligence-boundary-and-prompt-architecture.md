---
id: 017
title: Intelligence Boundary and Prompt Architecture
tier: P0
status: not-started
effort: 3 sessions
depends_on: [014, 015, 016]
findings: []
source_refs: [REQ-INT-001, REQ-INT-002, REQ-INT-003, REQ-INT-004, REQ-INT-005, REQ-INT-006, REQ-INT-007, REQ-INT-008, REQ-INT-009, REQ-INT-010, REQ-INT-011, REQ-INT-012, REQ-INT-013, REQ-INT-014, REQ-INT-015, REQ-INT-016, REQ-PRM-001, REQ-PRM-002, REQ-PRM-003, REQ-PRM-004, REQ-PRM-005, DEC-003]
tech_refs: [technology/01-foundation-models.md, technology/02-private-cloud-compute.md, technology/04-evaluations.md]
---

# 017 — Intelligence Boundary and Prompt Architecture

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§7 "Intelligence layer" and §11 "Prompt architecture" in full (prompt architecture
folded into this spec rather than split out — `PromptRegistry` is one component of
`IntelligenceService`, not a separate subsystem).

## Why

This is P3 made concrete: exactly one Swift module imports `FoundationModels`;
everything else — entry reflection, weekly/monthly synthesis, ask/chat — calls the
`IntelligenceService` protocol. Model choice, Z0/Z1 routing, PCC quota governance,
and degradation all live here, which is what makes provider swapping
(`REQ-INT-015`) a construction-site change instead of a rewrite. Also absorbs the
one deliberate capability regression of the rewrite: losing Supabase's DB-backed
`prompts` table with hot-reloadable versioning (§11.1) — replaced by bundled,
versioned Markdown prompts with an optional signed remote manifest.

## Technology References

- `specs/reference/technology/01-foundation-models.md` — primary:
  `LanguageModelSession`, `@Generable`/`@Guide`, the `LanguageModel` protocol
  (provider-swap seam for `REQ-INT-015`), `Tool`/`SpotlightSearchTool`,
  Dynamic Profiles, context sizes (4096/8192 on-device).
- `specs/reference/technology/02-private-cloud-compute.md` —
  `PrivateCloudComputeLanguageModel`, reasoning levels, `quotaUsage`, and the
  routing table/`QuotaGovernor` this spec builds.
- `specs/reference/technology/04-evaluations.md` — `REQ-PRM-004` prompt
  version traceability and the `Evaluations` framework this spec's outputs
  feed into (spec 022).

## Current State (evidence)

No direct Gemini SDK/HTTP calls exist in Swift — all LLM calls currently happen
server-side in Deno edge functions, called via `ChatService.swift`
(`MeetMemento/Services/ChatService.swift`) and `InsightsService.swift`. No
`IntelligenceService`-shaped protocol, no `@Generable`/guided generation, no
prompt registry exists client-side; prompt "versioning" today is an informally
synced Markdown file (`supabase/functions/chat/MEMENTO_SYSTEM_PROMPT.md` +
`docs/prompts/`), not a system.

## Requirements

- [ ] TODO (derive from source doc §7 and §11, per its §17 checklist): the full
  `IntelligenceService` protocol, `GenerationRequest`/`GenerationOutcome` contracts,
  and `@Generable` structs (`EntryReflection`, `PeriodReflection`) exactly as
  specified in source doc §7.1/§7.5 — do not redesign these, they're already
  fully specified there; the routing table (`REQ-INT-003`) as a literal
  data structure, not conditionals — **extended with a reasoning-level column**
  (`technology/02` §5: PCC exposes `.light`/`.moderate`/`.deep`; starting
  hypothesis weekly=`.moderate`, monthly=`.deep`, ask=`.light`, validated by
  spec 013's Spike B and spec 022's harness, per Apple's "data, not vibes" —
  noting reasoning tokens count against the 32K context); `QuotaGovernor` actor
  state machine (`REQ-INT-005`, `REQ-INT-006`) — the quota API surface is now
  ✅ **verified** (`technology/02` §6: `quotaUsage.status` → `.belowLimit(info)`,
  `info.isApproachingLimit`, `isLimitReached`, `limitIncreaseSuggestion.show()`),
  so only V4 remains open (per-app vs per-user scope; `limitIncreaseSuggestion`
  pointing at iCloud+ implies **per-user** — design the governor
  **reactive-first** on that assumption, with reservation as advisory, and treat
  a per-app answer as an upgrade, not the plan); when `isApproachingLimit`
  fires, chat degrades to Z0 first, preserving budget for scheduled reflections;
  degradation contract state machine (`REQ-INT-009`–`011`) with actual
  design-copy error taxonomy, not developer strings — the taxonomy MUST include
  **guardrail refusal as a designed state** (`technology/01` §11: journaling
  content — grief, illness, conflict — disproportionately trips safety
  guardrails; a refusal on the user's own entry renders as the
  `hasNothingToSay`-style empty state, e.g. "I don't have an observation for
  this one," never as an error and never implying judgment of what they wrote);
  **context budgeting as a contract**: never hardcode a token budget — read
  `SystemLanguageModel().contextSize` at runtime (4096 iOS 26 / 8192 iOS 27
  newer devices / 32768 PCC, ✅ verified), select entries by `salience` rather
  than dumping them (8K ≈ 25–30 entries *before* instructions, tools, and
  output), and use `response.usage` / `tokenCount(for:)` to detect retrieved
  entries crowding out the reflection; the **session-architecture decision**:
  evaluate iOS 27 Dynamic Profiles (`technology/01` §7 — one session declaratively
  swapping instructions/tools/model/reasoning between the reflect and ask modes)
  against the manual `transcript.dropFirstInstructions()` rebuild pattern, and
  record which one `IntelligenceService` uses; the image-understanding intent is
  **Z0-only with no degradation path — images are never sent to PCC**
  (`technology/01` §6); `PromptRegistry` interface (bundled Markdown + optional
  signed remote manifest per `REQ-PRM-001`–`003`) with `DEC-003` resolved
  (recommendation: build the mechanism, ship disabled, enable in 2.1);
  Given/When/Then acceptance criteria for `REQ-INT-015`'s provider escape hatch,
  exercised in a test target per its explicit requirement.

## Out of Scope

- The actual entry-reflection/weekly/monthly/ask *surfaces* that call this
  service — spec 019.
- TTS rendering of the resulting text — spec 018 (this spec only guarantees the
  text is speakable-shaped per `REQ-VOX-006`, enforced by that spec's
  `SpeakabilityLinter`).
- Monetization gating of which intents are free vs. paid — spec 021.

## Tasks
- [ ] 1. Define `IntelligenceService` protocol + `GenerationRequest`/
      `GenerationOutcome` (`REQ-INT-001`, `REQ-INT-002`).
- [ ] 2. Implement the table-driven router (`REQ-INT-003`, `REQ-INT-004`),
      including the reasoning-level column seeded from Spike B's recommendation.
- [ ] 3. Implement `QuotaGovernor` reactive-first (`REQ-INT-005`–`008`) against
      the verified `quotaUsage` surface; ⚠️ V4 (per-app vs per-user) and V13
      (full `status` case list) remain open — plan for per-user.
- [ ] 4. Implement degradation contract with design-copy error taxonomy
      (`REQ-INT-009`–`011`), including guardrail refusal as a designed
      `hasNothingToSay`-style state; log refusal rate against the fixture
      corpus (metric owned by spec 022).
- [ ] 5. Implement `@Generable` contracts exactly per source doc §7.5
      (`REQ-INT-012`, `REQ-INT-013`).
- [ ] 6. Implement snapshot streaming for chat only, non-streaming for
      reflections (`REQ-INT-014`).
- [ ] 7. Implement the `LanguageModel` injection seam + a test proving provider
      swap works (`REQ-INT-015`, `REQ-INT-016`).
- [ ] 8. Implement `PromptRegistry`: bundled Markdown prompts (`REQ-PRM-001`),
      optional signed remote manifest built but shipped disabled per `DEC-003`
      (`REQ-PRM-002`, `REQ-PRM-003`).
- [ ] 9. Persist `promptVersion`/`modelIdentifier` on every generated artifact
      (`REQ-PRM-004`); confirm spec 022's eval harness can consume it
      (`REQ-PRM-005`).
- [ ] 10. ⚠️ VERIFY item 14, latency half only (V28): context sizes are now
      ✅ verified (4096/8192/32768); measure on-device latency with the Xcode 27
      Foundation Models instrument **on the minimum supported Apple Intelligence
      device, not a current phone** — the p50 < 2s entry-reflection target
      (source doc §9.2) depends on it.
- [ ] 11. Decide the session architecture: Dynamic Profiles vs manual
      transcript-preserving rebuild; record the decision and rationale here.
- [ ] 12. Implement runtime context budgeting (read `contextSize`, rank by
      `salience`, instrument with `response.usage`); no hardcoded token numbers
      anywhere in the module.

## Verification
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must include a passing provider-swap test (`REQ-INT-015`) and items 4 and
      14 of the source doc's §16 verification queue each marked confirmed or
      outstanding.

## Regression Guards
`CONSTITUTION.md` §4 rule 5 ("exactly one Swift module imports `FoundationModels`")
is enforced by this spec and MUST be checkable by build configuration, not just
code review, before this spec can close. `CONSTITUTION.md` §4 rule 8
(`REQ-PRIV-001`) applies to every prompt this spec constructs — no journal content
in a Z1 prompt without the zone being correctly declared per spec 014.
