---
id: 016
title: Indexing and Retrieval — Core Spotlight
tier: P0
status: in-progress (2026-08-19) — **Branch B** per spec 013 DEC-002 (2026-08-19): not hidden; opt-in donation default off; `EntryRetriever` is the Ask/Find path
effort: 2 sessions
depends_on: [013, 014, 015]
findings: [dec-002-dual-branch-requirements, donation-pipeline-contracts, fallback-retrieval-tool, guidance-profile-split, recall-gate-automation, index-readiness-degradation]
source_refs: [REQ-IDX-001, REQ-IDX-002, REQ-IDX-003, REQ-IDX-004, REQ-IDX-005, REQ-IDX-006, REQ-IDX-007, REQ-IDX-008, REQ-IDX-009, REQ-IDX-010]
tech_refs: [technology/03-spotlight-retrieval.md]
---

# 016 — Indexing and Retrieval: Core Spotlight

**Branch declaration (spec 016 R1):** Branch B per spec 013 verdict of 2026-08-19 (`DEC-002` = not hidden). Named-index hiding is not available on `SpotlightSearchTool`. Donation is opt-in (`IndexingPreferences.spotlightOptIn`, default false). Retrieval is `EntryRetriever` (`REQ-IDX-007`). `IndexedEntity` follows the same opt-in.

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

**Traceability:** R1 → `DEC-002` (gate only — resolution owned by spec 013 R1);
R2 → `REQ-IDX-001`, `REQ-IDX-002`, `REQ-IDX-003`, `REQ-IDX-004`, `REQ-IDX-005`;
R3 → `REQ-IDX-005`, `REQ-IDX-006` (posture only), spec 015's `Entry.indexState`;
R4 → `REQ-IDX-006`, `REQ-IDX-007`; R5 → `technology/03` §5/§6/§9 + V9–V12;
R6 → `technology/03` §7; R7 → `REQ-IDX-008`, `REQ-IDX-009`; R8 → `REQ-IDX-010`;
R9 → `technology/03` §12 (V26); R10 → source doc §16 items 1 and 3.

**Zone tag (spec 014 R1):** every operation in this spec — donation, index
maintenance, vocabulary tagging at save, query execution, hydration — is
`.z0Device`. The index never leaves the device; a `LanguageModelSession` that
*consumes* the tool may itself be Z1 (spec 017's routing), but the retrieval
call the tool makes is local either way, which is what architecture §3.2 lists
under Z0 ("retrieval, search"). No operation here ever carries a
`.z1AppleContent` tag; any future change that would is a spec-014 R4 audit
failure, not a judgment call.

### Branch structure — read this before any R-block below

`DEC-002` (can Spotlight donation be hidden from system-wide search?) is
**unresolved** and stays unresolved in this spec — the verdict is produced by
spec 013 R1's real-device spike (Spike C, V1), currently blocked on Xcode 27
beta not being installed. This spec therefore specifies **both** outcomes:

- **Branch A — `DEC-002` positive.** Verdict "hidden" (named index /
  exclusion attribute works, cited API), or "partially hidden" with an explicit
  product sign-off accepting the documented caveat. Donation defaults on
  (`excludedFromIndex == false`); the full donation pipeline (R2) is the
  retrieval backbone.
- **Branch B — `DEC-002` negative.** Verdict "not hidden." `REQ-IDX-006`
  activates: `excludedFromIndex` defaults **true**, indexing becomes an
  explicit opt-in with plain-language tradeoff copy, and the `REQ-IDX-007`
  fallback tool (R4) becomes the retrieval path for the (presumably majority)
  non-opted-in users. The donation pipeline (R2) still ships for opt-in users —
  Branch B is "alongside," not "instead of," unless product later decides
  opt-in indexing isn't worth carrying.

Gating labels used below: **[Branch A]** / **[Branch B]** blocks are built only
when that branch's trigger fires; **[Unconditional]** blocks are built
regardless of the verdict. Nothing in this spec may be implemented in a way
that forecloses the other branch until spec 013's verdict is checked in.

### R1. [Unconditional] The `DEC-002` gate, restated as this spec's entry condition
This spec's implementation MUST NOT begin until spec 013 R1's written verdict
("hidden" / "partially hidden" / "not hidden", with cited API) exists in spec
013's Current State and is mirrored to `technology/11-verification-queue.md`
V1. The verdict selects the branch; this spec records which branch was taken
and why at the top of its own Current State when implementation starts.
**Acceptance:** a one-line branch declaration ("Branch A per spec 013 verdict
of YYYY-MM-DD" or "Branch B …") is present in this file before any Task is
checked off; no code in this spec's scope lands before that line exists.

### R2. [Branch A; also Branch B for opted-in users] Donation pipeline contracts
The four donation-side contracts, one code path serving Siri, Spotlight
actions, and the search tool (`REQ-IDX-002`):

```swift
// Donation (REQ-IDX-001): every Entry where excludedFromIndex == false.
// Attribute set MUST carry at minimum: full transcript as textual content,
// title, contentCreationDate, moodLabels, topics, placeName — and
// weatherSummary, which hydration (below) is expected to return.
func makeSearchableItem(from entry: Entry) -> CSSearchableItem

// IndexedEntity (REQ-IDX-002): same donation serves App Intents.
extension Entry: IndexedEntity { /* attributeSet built by the same maker */ }

// Hydration (REQ-IDX-003) — signature ✅ verified (technology/03 §4;
// compile-check only):
class EntryIndexDelegate: NSObject, CSSearchableIndexDelegate {
    func searchableItems(forIdentifiers identifiers: [String]) async -> [CSSearchableItem]
}
```

- **Hydration is load-bearing** (`technology/03` §4): the compact index does
  not carry the full transcript; `searchableItems(forIdentifiers:)` MUST
  return transcript + mood/topics/place/weather. Without it retrieval returns
  titles and every downstream reflection is vague and ungrounded — this is the
  difference between a working product and a plausible-sounding one, not
  polish.
- **Reindex extension** (`REQ-IDX-004`): a Spotlight index extension so the
  system can rebuild without launching the app. 🟡 LIKELY per `technology/03`
  §4 — confirm the extension point name against the SDK before scaffolding.
- **Incremental donation** (`REQ-IDX-005`): donate on save, remove on delete,
  in the same transaction boundary as the SwiftData write (spec 015's
  `indexState` is the record of whether that happened). A full-reindex path
  MUST exist and be triggerable from Settings ("Rebuild search index").
  **Inbound CloudKit rows** (spec 040) MUST be re-donated on this device —
  Spotlight is Z0 and does not replicate.
- **Index target is branch-dependent and verify-first:** Branch A's leading
  mechanism is a named index (`CSSearchableIndex(name: "memento-entries")`)
  rather than `.default()` — 🔴 unverified that `SpotlightSearchTool` can
  reach a named index (V1/V9). This spec does not assume it; it consumes spec
  013's verdict, which cites whichever API actually worked.
- **Lock gating** (`REQ-DATA-004`): index availability MUST respect device
  lock / Data Protection — spec 013 R1 test step 4 produces the evidence;
  this spec's acceptance re-checks it on the production pipeline.
- **Deletion hook** (`REQ-DATA-013`, spec 015): "delete everything" MUST
  remove all Spotlight items; leaving them behind is a P0 privacy defect
  (`technology/03` §10). Spec 015 owns the five-store deletion mechanics;
  this spec owns exposing a complete "remove all donations" operation for it
  to call.

**Acceptance (Given/When/Then):**
- Given an entry with `excludedFromIndex == false`, when it is saved, then a
  `CSSearchableItem` exists in the app's index whose attribute set carries all
  six `REQ-IDX-001` minimum fields, and `entry.indexState == .indexed`.
- Given an indexed entry, when it is deleted, then its item is removed from
  the index in the same operation — verified by querying the index, not by
  trusting the call returned.
- Given the model requests hydration for a result identifier, when
  `searchableItems(forIdentifiers:)` runs, then the returned item carries the
  full transcript plus mood/topics/place/weather — a unit test asserts
  field-by-field, against fixture entries.
- Given a real device (not simulator — system Spotlight behavior differs, spec
  013 R1), when fixture entries are donated through the production pipeline,
  then system-wide Spotlight shows none of them (Branch A) or only opted-in
  ones behave as the `DEC-002` verdict documented (Branch B).
- Given the device is locked, when the Data Protection window applies, then
  index items are unavailable per the spec-013 R1 step-4 finding.

### R3. [Unconditional] `Entry.indexState` state machine
Spec 015 defines the field (`.pending` / `.indexed` / `.excluded`); this spec
owns the transitions:

```
                       save (excludedFromIndex == false)
        ┌──────────┐  donation succeeds   ┌──────────┐
  new →─┤ .pending ├─────────────────────▶│ .indexed │
        └────┬─────┘                      └────┬─────┘
             │ user excludes entry /           │ user excludes /
             │ Branch B default posture        │ Branch B opt-out
             ▼                                 ▼ (donation removed)
        ┌───────────┐◀────────────────────────┘
        │ .excluded │──── user re-includes ──▶ .pending (re-donate on next save
        └───────────┘                          or immediately — pick one and test it)
```

- Donation failure leaves `.pending` (never a silent `.indexed` lie); the
  full-reindex path (R2) sweeps `.pending` entries.
- Entry deletion is not a state — the row and its index item cease to exist
  together (R2 acceptance).
- **Branch posture:** Branch A defaults `excludedFromIndex = false` (new
  entries enter at `.pending` → `.indexed`); Branch B defaults `true` (new
  entries enter `.excluded` until the user opts in, `REQ-IDX-006`).

**Acceptance:** a Swift Testing state-machine test drives every edge above
against an in-memory store + spy index and asserts no other transition is
reachable; a fixture entry whose donation call throws stays `.pending` and is
picked up by the rebuild path.

### R4. [Branch B] `REQ-IDX-007` fallback retrieval tool + `REQ-IDX-006` opt-in posture
**Trigger condition (explicit, per `REQ-IDX-007`):** spec 013 R1's verdict is
"not hidden." Until that verdict, this R-block is a designed contingency —
specified here, unbuilt.

A hand-rolled `Tool` (Foundation Models tool protocol) querying SwiftData
directly — no system index involvement, journal text never leaves the app's
own store:

```swift
struct EntryQueryTool: Tool {
    static let name = "searchJournal"
    // description tuned so the model prefers searching over answering
    // from world knowledge

    @Generable
    struct Arguments {
        @Guide(description: "Inclusive date range to search, if the question is temporal.")
        var dateRange: DateInterval?
        @Guide(description: "Keywords to match against entry text.")
        var keywords: [String]?
        @Guide(description: "Mood labels from the fixed vocabulary (R7).")
        var moods: [String]?
        @Guide(description: "Topics from the fixed vocabulary (R7).")
        var topics: [String]?
    }
    // Returns top-N entries as structured tool output: id, date, title,
    // transcript excerpt, moods, topics, place — same hydration-completeness
    // rule as R2; a fallback that returns titles is the same failure.
}
```

Matching: date-range predicates + `NLTagger`-derived keyword matching +
mood/topic filters, top-N ranked. Materially weaker than semantic retrieval —
stated plainly, not hidden — but keeps the architecture serverless.

`REQ-IDX-006` posture: `excludedFromIndex` defaults **true**; indexing is an
explicit opt-in surfaced with a plain-language tradeoff explanation (design
copy, not developer strings — draft: *"Let iPhone search include your journal?
Answers get better, but entries may appear in system-wide search on this
device."* — final wording owned by design). Retrieval routes per entry-set:
opted-in content through `SpotlightSearchTool`, everything else through
`EntryQueryTool`.

**Acceptance (Given/When/Then):**
- Given Branch B and a fresh install, when the first entry is saved, then
  `excludedFromIndex == true`, `indexState == .excluded`, and no Spotlight
  donation call was made (spy index asserts zero donations).
- Given the fallback tool and the fixture corpus loaded into SwiftData, when
  the gold questions run (R8), then recall@5 is measured and recorded for the
  fallback path *separately* from the Spotlight path — the 0.85 bar applies to
  whatever path ships as default; if the fallback cannot reach it, that is an
  escalation to product (ship-blocker per `REQ-IDX-010`), never a silently
  waived gate.
- Given a temporal question ("when did I first say I was burnt out?"), when
  the model calls the tool, then the tool's structured output contains
  `e-2026-01-12-1` (fixture anchor) in its top-5.

### R5. [Unconditional — applies wherever `SpotlightSearchTool` runs, i.e. all of Branch A and Branch B's opted-in path] Session-side retrieval contracts
- **Two guidance-profile configurations, not one** (`technology/03` §6, ✅
  verified), as named, unit-tested constants (e.g. `RetrievalGuidance.z0Focused`
  / `RetrievalGuidance.z1Dynamic`), never inline per call site:
  - Z0 (on-device, 8K context): `guide: .init(level: .focused(.items))` —
    Apple's own comment: "on-device models have smaller context — prefer
    focused guidance."
  - Z1 (PCC, 32K): `.dynamic(profile)` with `textMatch: true`, `dates: true`
    (nearly every journal question is temporal), `people: true`, plus
    mood/topic/place attributes.
- **`queryToken` handling** (`technology/03` §5, ✅ verified): the model may
  call the tool multiple times per response; result consumption MUST section
  results by `reply.queryToken` or two searches merge into one list. All seven
  `reply.content` cases (`.items`/`.scoredItems`/`.groupedItems`/`.count`/
  `.table`/`.statistic`/`.text`) are handled — the computed cases are what
  spec 019 renders as richer-than-chat-bubble UI.
- **Custom pipeline stages** (`technology/03` §9, ✅ verified): specify
  `MoodValenceStage`, `SalienceStage`, `RecurrenceStage` (`.items` →
  `.scoredItems`/`.groupedItems`), `CadenceStage` (`.items` → `.statistic`).
  Rule: **prefer a stage over asking the model to count** — computation moves
  into the retrieval loop instead of the LLM approximating arithmetic over
  prose, which is exactly how journaling apps produce confidently wrong
  pattern claims. These stages are what make spec 019's Patterns surface and
  `REQ-SUR-001`'s honest-n claims computable. Each stage gets unit tests over
  the fixture corpus with known-correct outputs (e.g. `CadenceStage` over the
  overcast-Monday motif returns the count `validate_corpus.py` materialized).
- **Verify-first criteria — 🔴 claims are acceptance gates, not assumptions**
  (V9–V12; spec 013 task 8 may have closed some — check the V-queue before
  spending effort). Before this R-block's implementation is considered
  specified-complete:
  - V9: `Configuration.sources` full case list enumerated from the SDK (also
    feeds R2's index-target question).
  - V10: tool registration form confirmed — instance (`tools: [tool]`) vs
    metatype (`tools: [MyTool.self]`).
  - V11: `GenerationOptions.ToolCallingMode` existence confirmed or refuted —
    if it exists, the Ask surface wants "always search, never answer from
    world knowledge."
  - V12: the registered tool name string confirmed (Apple's sample implies
    `"searchSpotlight"`) — R8's trajectory expectations depend on the exact
    string.

**Acceptance:** the two guidance constants exist with a test asserting their
configured fields; a consumption test feeds two interleaved `queryToken`
streams and asserts no cross-merge; each of V9–V12 is marked ✅ (with the
confirmed surface noted) or explicitly outstanding in
`technology/11-verification-queue.md` before Tasks 8–10 are checked off.

### R6. [Unconditional] `ContactResolver` privacy rule
Never pull from the Contacts framework — requesting address-book access in a
private journal is an unforced trust cost and introduces data Memento has no
business holding. Resolve identity from the **locally stored display name**
collected in onboarding (spec 023 R3's local name cache — there are no
accounts, so `technology/03` §7's original "Sign in with Apple profile" source
no longer exists): enough to distinguish "I"/"me" from other names. Richer
person-resolution comes from names the user themselves wrote in entries, or
not at all. Applies identically to Branch B's fallback tool (person-keyword
matching uses the same rule).
**Acceptance:** the resolver returns a `ResolvedContact` built solely from the
onboarding name cache; CI greps the app target for `import Contacts` and fails
on any hit (same mechanism as spec 014 R3's forbidden-phrase lint); no
Contacts-related `Info.plist` usage string exists.

### R7. [Unconditional] Controlled vocabularies (`REQ-IDX-008`, `REQ-IDX-009`)
`moodLabels` and `topics` MUST be drawn from a fixed, versioned vocabulary
defined in the repo, not free-generated — free-form tags fragment the index,
make pattern detection statistically meaningless, and produce reflections that
claim trends that don't exist.
- **Versioning scheme:** one repo-checked-in vocabulary file, a monotonically
  increasing integer `vocabularyVersion`, stamped on every entry at tagging
  time so a future vocabulary migration can re-tag (`REQ-IDX-009`). A version
  bump ships with a migration task that re-tags stamped-older entries; entries
  are never left mixing vocabularies without a recorded version telling the
  pattern stages so.
- **Assignment:** guided generation (`@Generable` with enum-constrained
  fields) on-device at entry save — Z0, per the zone tag above; ≤3 moods, ≤4
  topics per entry (matching the fixture schema).
- **The actual value list is out of scope here** (see Out of Scope) — but the
  fixture corpus's working vocabulary (12 moods / 12 topics,
  `Fixtures/README.md`, explicitly written to "mirror the app's fixed enums,
  spec 016 `REQ-IDX-008`") is the de-facto v1 candidate; whatever list is
  adopted MUST keep the fixture corpus valid or update it and re-run
  `Fixtures/validate_corpus.py` in the same change.

**Acceptance (Given/When/Then):** given an entry saved with tagging enabled,
when guided generation runs, then every assigned label is a member of the
versioned vocabulary (enum-constrained — a compile-time guarantee, tested
anyway against the decoded output) and `vocabularyVersion` is stamped; given a
version bump from N to N+1, when migration runs, then no entry remains stamped
N without a recorded decision to skip it.

### R8. [Unconditional] `REQ-IDX-010` retrieval quality gate — automated, pre-ship, re-runnable
The gate: **recall@5 ≥ 0.85** on the gold set, measured against spec 013 R4's
fixture corpus (`Fixtures/corpus/entries-YYYY-MM.json`, 262 entries / 9
months) and gold questions — **`Fixtures/gold/questions.resolved.json`** (45
questions; the resolved file is the eval input because `validate_corpus.py`
materializes the 4 pattern-derived questions' `expectedEntryIDs` into it).
This is an automated, CI-runnable check built on the `Evaluations` framework
with `expectedIdentifiers` per query (`technology/04` §2), shared with spec
022's harness — **not** a one-time spike result. Spec 013 R2 (Spike A)
produces the *first* measurement; this R-block turns it into a *standing*
gate.
- Scoring: for each question, retrieval's top-5 is checked against
  `expectedEntryIDs` under the question's `match` semantics; recall@5 is the
  fraction of questions satisfied. Per-category numbers (temporal / person /
  event / synthesis / pattern / honesty) are reported alongside the aggregate
  so a regression in one category can't hide inside a passing average.
- Branch coverage: run against the Spotlight path (Branch A / opted-in), and
  in Branch B *also* against the fallback tool (R4 acceptance) — two recorded
  numbers, each compared to the same 0.85 bar for whichever path is a shipping
  default.
- Trajectory expectations (`ToolExpectation(<tool name>, …)`) use the V12
  registered-name string once confirmed — 🔴 until then.

**Acceptance (Given/When/Then):**
- Given the fixture corpus donated/loaded and the resolved gold set, when the
  gate runs in CI, then it outputs aggregate + per-category recall@5 and fails
  the build if aggregate < 0.85.
- Given any change to donation attributes, guidance profiles, custom stages,
  or the vocabulary version, when CI runs, then the gate re-runs — it is wired
  as a required check for this spec's surface area, not an on-demand script.
- Given the gate has never passed, when any generative surface depending on
  retrieval (specs 017/019) is proposed for ship, then that ship is blocked —
  the gate is a precondition stated here so 017/019 can cite it.

### R9. [Unconditional] Index-readiness degradation (V26 — verify-first)
iOS 27 rebuilds the system search index on update; on large libraries the
"Indexing in Progress" state can persist for days, during which retrieval may
be degraded (`technology/03` §12). 🔴 UNVERIFIED whether an API exposes
index-readiness state — so this R-block is two contracts, one gated on the
investigation's outcome:
- **Investigate first** (Task 12): determine whether readiness is queryable in
  the iOS 27 SDK. Record the answer in `technology/11-verification-queue.md`
  V26 either way.
- **Either way, design the degraded state:** the Ask surface (spec 019) MUST
  have a designed "retrieval may be incomplete right now" state rather than
  silently returning nothing. If readiness is queryable, the state is entered
  on that signal; if not, specify the heuristic fallback (e.g. post-update
  window + anomalously empty results) and label it as a heuristic in the
  design.

**Acceptance:** V26 marked ✅ (API cited) or ✅-negative (no API; heuristic
specified) — never left 🔴; the degraded-state contract (trigger, copy intent,
recovery) is written in this spec or handed to spec 019 with a citation back
here before 019's Ask surface is finalized.

### R10. [Unconditional] This spec's §16 verification-queue ownership
Per the spec's Traceability and the source doc's §16 numbering map:
- **§16 item 1** (`SpotlightSearchTool` exact API surface → V9–V12): **partially
  resolved** — core API ✅ verified (init, configuration, `searchResults`
  cases, guidance profiles; `technology/03` §2–§6); outstanding: `sources`
  case list (V9), registration form (V10), `ToolCallingMode` (V11), registered
  tool name (V12). Owned here via R5's verify-first criteria; spec 013 task 8
  may close them first — check the V-queue before duplicating effort.
- **§16 item 3** (`searchableItems(forIdentifiers:)` signature): **already ✅
  resolved** per the source doc's own numbering map and `technology/03` §4 —
  compile-check only when R2's delegate lands; no research remaining.
- **§16 item 2** (`DEC-002`, V1) is explicitly **not** owned here — spec 013
  R1 owns it; this spec only consumes the verdict (R1 above).

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
- [ ] Branch declaration exists at the top of Current State ("Branch A/B per
      spec 013 verdict of YYYY-MM-DD") before any Task is checked off (R1) —
      and the branch built matches spec 013's recorded `DEC-002` verdict.
- [ ] **Automated recall@5 gate (R8):** the `Evaluations`-framework check runs
      in CI against `Fixtures/corpus/` + `Fixtures/gold/questions.resolved.json`,
      reports aggregate + per-category recall@5, and fails the build below
      0.85. Re-runnable on every change to donation attributes, guidance
      profiles, stages, or vocabulary version — verified by triggering it from
      a trivial change, not by reading the workflow file. In Branch B, a second
      recorded number covers the fallback tool path.
- [ ] **§16 item 1** (V9–V12): each of `sources` case list, tool-registration
      form, `ToolCallingMode`, and registered tool name marked ✅ confirmed
      (surface noted) or explicitly outstanding in
      `technology/11-verification-queue.md` — core `SpotlightSearchTool` API is
      already ✅; only these four remain (R5, R10).
- [ ] **§16 item 3** (`searchableItems(forIdentifiers:)`): already ✅ resolved
      per the source doc's numbering map (`technology/03` §4) — confirm by
      compile-check when R2's delegate lands; record "confirmed" here, no
      research step.
- [ ] Hydration test passes: retrieval of a fixture entry returns full
      transcript + mood/topics/place/weather field-by-field, never titles-only
      (R2).
- [ ] Real-device check on the production pipeline (not the spike, not the
      simulator): donated fixture entries do not appear in system-wide
      Spotlight (Branch A) / only per the documented opt-in posture (Branch B);
      locked-device behavior matches spec 013 R1 step-4's finding (R2).
- [ ] `Entry.indexState` state-machine test drives every R3 edge; a
      failing-donation fixture stays `.pending` and is swept by "Rebuild search
      index" (R2, R3).
- [ ] Branch B only: fresh-install default is `excludedFromIndex == true` /
      `.excluded` with zero donation calls; `EntryQueryTool` returns
      `e-2026-01-12-1` in top-5 for the burnout gold question (R4).
- [ ] Guidance-profile constants exist with field-assertion tests; interleaved
      `queryToken` consumption test shows no cross-merge; all four custom
      stages have fixture-corpus unit tests with known-correct outputs,
      including `CadenceStage` matching `validate_corpus.py`'s materialized
      overcast-Monday count (R5).
- [ ] CI grep: no `import Contacts` and no Contacts usage-string in the app
      target; `ContactResolver` sources identity only from spec 023's local
      name cache (R6).
- [ ] Vocabulary file is repo-checked-in and versioned; every tagged entry
      carries `vocabularyVersion`; `Fixtures/validate_corpus.py` still passes
      after any vocabulary change (R7).
- [ ] V26 closed in either direction (readiness API cited, or no-API +
      specified heuristic) and the degraded-state contract handed to spec 019
      (R9).
- [ ] All retrieval/indexing call sites tag `.z0Device` and are picked up by
      spec 014 R4's `NetworkCallSiteAudit` once it exists — this spec adds no
      network call sites at all.
- [ ] "Delete everything" (spec 015 `REQ-DATA-013`) leaves zero items in the
      app's Spotlight index — queried, not assumed (R2).

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
