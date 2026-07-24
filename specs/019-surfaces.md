---
id: 019
title: Surfaces — Capture, Reflection, Weekly, Patterns, Ask
tier: P1
status: not-started
effort: 4 sessions
depends_on: [016, 017, 018]
findings: []
source_refs: [REQ-SUR-001, REQ-SUR-002, REQ-SUR-003, REQ-SUR-004, REQ-SUR-005]
tech_refs: [technology/03-spotlight-retrieval.md, technology/07-app-intents-and-surfaces.md, technology/09-ui-swift6-testing.md]
---

# 019 — Surfaces: Capture, Reflection, Weekly, Patterns, Ask

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§9 "Surfaces" in full. Supersedes spec [010](010-chat-reliability.md) (chat
reliability and error contract — obsolete; its "Ask" replacement is `REQ-SUR-002`–
`004` here, plus `REQ-SUR-005`'s honest-retry contract for the background jobs
that generate weekly/monthly content in the first place).

## Why

Where the intelligence boundary (spec 017) and capture/voice (spec 018) become
visible product. Build order is prescriptive per the source doc: Capture →
Entry reflection → Weekly → Patterns/Monthly → Ask, each with its own zone,
degradation story, and exit criterion — Ask last because it's highest variance,
highest PCC-quota consumption, and highest safety surface (crisis-adjacent
content routing, `REQ-SUR-004`).

## Technology References

- `specs/reference/technology/03-spotlight-retrieval.md` — Ask surface's
  tool-calling loop over `SpotlightSearchTool`, reply content cases
  (items/scoredItems/table/statistic/text).
- `specs/reference/technology/07-app-intents-and-surfaces.md` —
  `BGProcessingTask`/`BGProcessingTaskRequest` scheduling for background
  weekly/monthly generation (`REQ-SUR-005`).
- `specs/reference/technology/09-ui-swift6-testing.md` — Swift Charts for
  Patterns/Monthly, with the mandatory sample-size disclosure rule.

## Current State (evidence)

Current chat/insights surfaces (`ChatService.swift`, `InsightsService.swift`,
associated Views) are built against the Supabase `chat` and `generate-insights`
edge functions being deleted in spec 015/016 — they are not incrementally
upgradable and will be rebuilt against `IntelligenceService` (spec 017), not
patched.

## Requirements

- [ ] TODO (derive from source doc §9, per its §17 checklist, one surface at a
  time in build order): Capture surface exit criterion (§9.1, shared with spec
  018); Entry reflection exit criterion (§9.2: p50 < 2s, observation suppressed
  on ≥ 60% of ordinary entries); Weekly reflection (§9.3: `BGProcessingTask`
  scheduling, citation tap-through, `hasNothingToSay` real empty state, ≥ 80%
  "worth reading" / ≥ 95% citation accuracy exit bar — these are spec 022's
  metrics to *measure*, this spec's job to make *measurable*); Patterns/Monthly
  (§9.4: Swift Charts with `REQ-SUR-001`'s mandatory n-shown-per-correlation);
  Ask (§9.5: `SpotlightSearchTool` tool-calling loop, archivist-not-therapist
  persona enforced in system instructions and adversarially evaluated per
  `REQ-SUR-002`, "don't know" honesty per `REQ-SUR-003`, crisis-adjacent static
  resource card per `REQ-SUR-004` — route the full crisis-content policy to a
  dedicated `safety.spec.md`-equivalent if this grows beyond a subsection;
  **promoted from spec [012](012-post-launch-backlog.md)'s parking lot,
  2026-07-23**: prompt-injection hardening against the tool-calling loop itself —
  a materially different threat model than today's single-shot chat, since Ask
  can be steered by content the model retrieves from the user's own entries, not
  just the user's direct question);
  background generation retry/fallback contract (`REQ-SUR-005`).

  **Mounting and preservation (2026-07-23):** every surface this spec builds
  mounts on the preserved shell per the `ATTACH` map in
  `specs/reference/frontend-preservation-contract.md` §3 — Ask replaces the
  Insights tab's backing service and MUST restore the chat end-state invariants
  (PRES-040…048: three-state input, suggestion cards, typewriter output with
  copy/thumbs/regenerate, citations sheet, history sheet, summarize-to-entry,
  failure/gating states) intact; Weekly mounts as a card atop the Journal
  timeline (ATTACH-02); **Patterns mounts as a third pill tab** (ATTACH-03 —
  the one sanctioned amendment to PRES-004, decided 2026-07-23), and MUST
  evaluate the contract's §4 reuse ledger first (the deprecated chart subsystem
  — `SentimentAnalysisCard`, `PercentageBarChart` with WCAG-AAA emotion tokens,
  `KeywordsCard`, `FollowUpQuestionGroup` — is a substantially built starting
  point); entry reflection renders on the entry surface (ATTACH-04).

  Additions from the verified tool surface and system-integration constraints:
  - **Ask renders computed answers, not just prose** (`technology/03` §5): the
    tool's reply stream carries `.count`/`.statistic`/`.table`/`.scoredItems`
    cases with a display `label` — "how many times did I write about my brother
    this year?" gets a computed number, not a prose guess. Track
    `reply.queryToken` per section: the model may call the tool multiple times
    per response, and unmerged tokens are the difference between a coherent
    results UI and two searches blended into one list. This is the richer-than-
    a-chat-bubble surface a design-led product should spend on.
  - **Trajectory enforcement of `REQ-SUR-003`**: "never answer from world
    knowledge" is verified mechanically — spec 022's harness asserts via
    `TrajectoryExpectation` that the search tool was called on 100% of Ask
    queries (`technology/04` §3). This spec's job is to keep the surface's
    prompt/tool wiring compatible with that assertion.
  - **Notifications, exhaustively** (`technology/07` §8): exactly two exist —
    an opt-in daily reminder (off by default) and "your weekly reflection is
    ready." Weekly-ready is part of this spec's §9.3 surface. Nothing else,
    ever: no "you haven't written in N days," no re-engagement campaigns
    (NON-GOAL: notification-driven engagement loops). Background scheduling is
    best-effort — promise "Sunday morning," never an exact time.

## Out of Scope

- The underlying generation calls — spec 017 (this spec is UI/UX/flow; 017 is the
  service layer it calls).
- TTS playback mechanics — spec 018 (this spec decides *which* surfaces are
  listenable; 018 owns *how* playback works).
- A full crisis-intervention/safety spec — `REQ-SUR-004` is scoped here as
  "surface a static resource card," not clinical policy design; escalate to a
  dedicated spec if that scope grows.

## Tasks
- [ ] 1. Rebuild Capture surface against spec 018's capture pipeline; verify
      §9.1 exit criterion.
- [ ] 2. Build Entry reflection surface against spec 017's `IntelligenceService`;
      verify §9.2 exit criterion (latency + suppression rate against spec 013's
      fixture corpus).
- [ ] 3. Build Weekly reflection: `BGProcessingTask` scheduling, citation
      tap-through, `hasNothingToSay` state (`REQ-INT-013`).
- [ ] 4. Build Patterns/Monthly: Swift Charts + `REQ-SUR-001` n-disclosure.
- [ ] 5. Build Ask: `SpotlightSearchTool` loop, persona enforcement, crisis card
      (`REQ-SUR-002`–`004`).
- [ ] 6. Implement background-generation retry/fallback contract
      (`REQ-SUR-005`).
- [ ] 7. Delete the old `ChatService.swift`/`InsightsService.swift`/associated
      Views once their replacements are verified, not before.
- [ ] 8. Decide whether to split this spec into per-surface specs
      (`/specs/surfaces/*` in the source doc's own naming) if a future session
      finds the combined scope unwieldy — noted as an open call, not decided now.

## Verification
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must include each surface's exit criterion from source doc §9 measured
      against spec 013's fixture corpus, and an adversarial persona-adherence
      pass for Ask (`REQ-SUR-002`).
- [ ] Chat end-state restoration checklist: every PRES-040…048 behavior from
      `frontend-preservation-contract.md` §2.3 verified working on the rebuilt
      Ask surface — this closes the contract's "end-state invariants" window
      that opened when Phase 1 took the edge functions down.

## Regression Guards
None of the current chat/insights UI is preserved as a DO-NOT-REGRESS baseline —
it's being replaced, not migrated. The guarantee that does carry forward:
citation accuracy and non-fabrication (originally `CONSTITUTION.md` §2 *Backend*,
now `REQ-DATA-005` in spec 015) must hold in the new Ask/Weekly/Monthly surfaces
before this spec can close.
