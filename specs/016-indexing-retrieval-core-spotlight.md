---
id: 016
title: Indexing and Retrieval — Core Spotlight
tier: P0
status: not-started
effort: 2 sessions
depends_on: [013, 014, 015]
findings: []
source_refs: [REQ-IDX-001, REQ-IDX-002, REQ-IDX-003, REQ-IDX-004, REQ-IDX-005, REQ-IDX-006, REQ-IDX-007, REQ-IDX-008, REQ-IDX-009, REQ-IDX-010]
tech_refs: [technology/03-spotlight-retrieval.md]
---

# 016 — Indexing and Retrieval: Core Spotlight

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§6 "Indexing and retrieval" in full. Supersedes spec
[004](004-edge-function-security-and-cost.md) (edge function security/cost —
obsolete; the LLM-cost-control concern this spec protected carries forward as
`QuotaGovernor` in spec 017, not here).

## Why

Replaces the entire 1.3 pgvector RAG subsystem (embeddings pipeline, vector store,
retrieval edge function) with donation to Core Spotlight's semantic index plus a
`SpotlightSearchTool`-equipped `LanguageModelSession`. This is contingent on spec
013's Spike A having passed and `DEC-002` (can donations be hidden from
system-wide search) having been resolved — if `DEC-002` resolved negatively, this
spec builds the `REQ-IDX-007` fallback tool instead of/in addition to Spotlight
donation.

## Technology References

- `specs/reference/technology/03-spotlight-retrieval.md` — primary:
  `SpotlightSearchTool` configuration and `GuidanceProfile` levels,
  `CSSearchableIndexDelegate` hydration, `tool.searchResults` reply content
  cases, `ContactResolver`, custom pipeline stages, and the `DEC-002`
  visibility question this spec's `REQ-IDX-007` fallback tool depends on.

## Current State (evidence)

No Core Spotlight or App Intents integration exists anywhere in `MeetMemento/`
(confirmed 2026-07-23) — this is fully greenfield. Spec 013's Spike A is a
throwaway prototype; this spec builds the real, incremental-on-save/delete
pipeline.

## Requirements

- [ ] TODO (derive from source doc §6, per its §17 checklist): interface
  contracts for the donation pipeline (`CSSearchableItemAttributeSet` construction,
  `CSSearchableIndexDelegate` including `searchableItems(forIdentifiers:)` —
  signature now ✅ verified, `technology/03` §4; compile-check only), the
  `IndexedEntity` conformance shared with App Intents (`REQ-IDX-002`), and the
  reindex extension (`REQ-IDX-004`); state machine for `Entry.indexState`
  transitions on save/delete/exclude; the controlled-vocabulary versioning scheme
  for `moodLabels`/`topics` (`REQ-IDX-008`, `REQ-IDX-009`); Given/When/Then
  acceptance criteria for the `REQ-IDX-010` retrieval quality gate (recall@5 ≥
  0.85 against spec 013's fixture corpus) as an automated, pre-ship, re-runnable
  check — not a one-time spike result.

  Additions from the verified `SpotlightSearchTool` surface (`technology/03`),
  each a contract this spec must specify, not optional polish:
  - **Hydration is load-bearing** (§4): the compact index does not carry the full
    transcript; without `searchableItems(forIdentifiers:)` returning transcript +
    mood/topics/place/weather, retrieval returns titles and every downstream
    reflection is vague and ungrounded.
  - **Two guidance-profile configurations, not one** (§6): Z0 (on-device,
    8K context) uses `guide: .init(level: .focused(.items))`; Z1 (PCC, 32K) uses
    `.dynamic(profile)` with `textMatch: true`, `dates: true` (nearly every
    journal question is temporal), `people: true`, plus mood/topic/place
    attributes. Apple's own comment: "on-device models have smaller context —
    prefer focused guidance."
  - **Custom pipeline stages** (§9): specify `MoodValenceStage`, `SalienceStage`,
    `RecurrenceStage`, `CadenceStage` (`.items` → `.scoredItems`/`.groupedItems`/
    `.statistic`). Rule: **prefer a stage over asking the model to count** —
    computation moves into the retrieval loop instead of the LLM approximating
    arithmetic over prose, which is exactly how journaling apps produce
    confidently wrong pattern claims. These stages are what make spec 019's
    Patterns surface and `REQ-SUR-001`'s honest-n claims computable.
  - **`ContactResolver` privacy rule** (§7): never pull from the Contacts
    framework — requesting address-book access in a private journal is an
    unforced trust cost. Resolve identity from the **locally stored display
    name** collected in onboarding (spec 023 R2/R3 — there are no accounts, so
    the earlier "Sign in with Apple profile" source no longer exists); richer
    person-resolution comes from names the user themselves wrote in entries, or
    not at all.
  - **Index-readiness degradation** (§12, V26): iOS 27 rebuilds the system index
    on update (can take days on large libraries); retrieval may be degraded
    meanwhile. Detect and communicate this state on the Ask surface rather than
    silently returning nothing — investigate whether readiness is queryable.

## Out of Scope

- Resolving `DEC-002` itself and the initial recall@5 measurement — that's spec
  013's Spike A/C. This spec builds the production pipeline once those are
  resolved.
- The Foundation Models tool-calling loop that consumes retrieval results in
  chat/ask — spec 017 (intelligence boundary) and spec 019 (Ask surface).
- The controlled vocabulary's actual mood/topic value list — content decision,
  not architecture; may be filed as a follow-up task inside this spec rather than
  decided here.

## Tasks
- [ ] 1. Implement `CSSearchableItemAttributeSet` donation on entry save
      (`REQ-IDX-001`), incremental on save/delete (`REQ-IDX-005`).
- [ ] 2. Implement `IndexedEntity` conformance (`REQ-IDX-002`).
- [ ] 3. Implement `CSSearchableIndexDelegate` + `searchableItems(forIdentifiers:)`
      (`REQ-IDX-003`) — ⚠️ VERIFY item 3.
- [ ] 4. Implement the Spotlight index extension for background reindexing
      (`REQ-IDX-004`) + a Settings "Rebuild search index" action (`REQ-IDX-005`).
- [ ] 5. If `DEC-002` resolved negatively in spec 013: implement the
      `REQ-IDX-007` SwiftData-query fallback tool (Plan B) instead of/alongside
      Spotlight donation; default `excludedFromIndex` to `true` with opt-in UI
      per `REQ-IDX-006`.
- [ ] 6. Implement controlled vocabulary versioning (`REQ-IDX-008`, `REQ-IDX-009`).
- [ ] 7. Wire the `REQ-IDX-010` recall@5 gate as an automated, re-runnable check
      against spec 013's fixture corpus (not a one-time spike) — built on the
      `Evaluations` framework with `expectedIdentifiers` per query
      (`technology/04` §2), shared with spec 022.
- [ ] 8. ⚠️ VERIFY item 1 (V9–V12): core `SpotlightSearchTool` API is verified;
      confirm the remaining surface — `Configuration.sources` case list,
      tool-registration form (instance vs metatype), `ToolCallingMode`
      existence, registered tool name — before finalizing the donation
      attribute set. (Spec 013 task 8 may have already closed these; check the
      V-queue first.)
- [ ] 9. Implement the two guidance-profile configurations (Z0 focused / Z1
      dynamic) as named, tested constants — not inline per call site.
- [ ] 10. Implement the four custom pipeline stages (`MoodValenceStage`,
      `SalienceStage`, `RecurrenceStage`, `CadenceStage`) with unit tests over
      the fixture corpus.
- [ ] 11. Implement `ContactResolver` from the locally stored display name
      (spec 023); assert no Contacts-framework import anywhere in the app
      target.
- [ ] 12. Investigate index-readiness detection (V26); design the degraded-state
      communication for spec 019's Ask surface either way.

## Verification
- [ ] TODO — derive concrete test/review steps once Requirements are written;
      must include an automated recall@5 ≥ 0.85 run against spec 013's fixture
      corpus as a pre-ship, CI-runnable gate, plus items 1 and 3 of the source
      doc's §16 verification queue each marked confirmed or outstanding.

## Regression Guards
`CONSTITUTION.md` §2 *Backend* subsection's retired citation-integrity guarantee
("citations can't be fabricated cross-user") carries forward as `REQ-DATA-005`
(spec 015) — this spec's retrieval results feed that guarantee and must not
reintroduce a way to surface another user's data (moot on-device, but re-verify
CloudKit-shared-database exposure is genuinely never used, per `REQ-DATA-001`'s
"no public or shared database"). Preservation contract: PRES-026 (local entry
search behavior in the search overlay, PRES-008) must be preserved whether or
not this spec routes it through Spotlight — the user-facing search experience
does not change when the backing index does.
