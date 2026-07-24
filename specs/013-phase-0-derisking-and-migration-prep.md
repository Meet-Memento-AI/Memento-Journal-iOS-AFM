---
id: 013
title: Phase 0 — De-risking Spikes and Migration Prep
tier: P0
status: in-progress (2026-07-23)
effort: 2 sessions
depends_on: []
findings: [dec-002-spotlight-visibility, pcc-application-lead-time, journaling-suggestions-entitlement, fixture-corpus-missing, spike-a-spotlight-retrieval, spike-b-reflection-quality, legacy-spec-reaudit]
source_refs: [REQ-MIG-001, REQ-IDX-010, DEC-002]
tech_refs: [technology/11-verification-queue.md, technology/03-spotlight-retrieval.md, technology/01-foundation-models.md, technology/02-private-cloud-compute.md]
---

# 013 — Phase 0: De-risking Spikes and Migration Prep

**Traceability:** derives from `specs/reference/memento-2.0-architecture-spec.md`
§14.2 "Phase 0 — De-risk" and §6.3 "The visibility problem." This is the first spec
of the Memento 2.0 rewrite (see `ROADMAP.md`'s "2.0 Rewrite — Phase Plan"). Nothing
is deleted in this phase — it is pure research and filing.

## Why

The 2.0 rewrite (deleting Supabase/pgvector/Gemini for SwiftData + Core Spotlight +
Foundation Models) rests on three unverified assumptions: that Spotlight retrieval
quality is good enough to replace pgvector RAG, that Spotlight donations can be kept
out of system-wide search (a private journal entry surfacing in a stranger's phone
search is a category-ending failure, not a bug), and that the entitlements/program
enrollments the architecture depends on can actually be obtained in time. Phase 1
(deleting the backend) MUST NOT start until these are resolved — deleting a working
system before its replacement is proven is the one mistake this phase exists to
prevent.

## Technology References

- `specs/reference/technology/11-verification-queue.md` — primary: resolving
  🔴 V1 (Spotlight system-search visibility, `DEC-002`) and V2/V3/V4 (PCC
  application lead time, Journaling Suggestions entitlement lead time, PCC
  per-app-vs-per-user quota) is this spec's job.
- `specs/reference/technology/03-spotlight-retrieval.md` §8 — the visibility
  problem writeup Spike A/C tests against.
- `specs/reference/technology/01-foundation-models.md` and
  `specs/reference/technology/02-private-cloud-compute.md` — API surface
  Spike B (on-device vs PCC vs current Gemini reflection quality) exercises.

## Current State (evidence)

| # | Problem | Evidence | Severity |
|---|---|---|---|
| 0 | **Toolchain: Xcode 26.0.1 / iOS 26 SDK installed — Xcode 27 beta NOT installed** (checked 2026-07-23, `xcodebuild -version`). Blocks Spikes A/B/C and the task-8 API sweep (`SpotlightSearchTool`, PCC, AFM3 are iOS 27). R4 corpus + R7 manifest check proceed regardless. | `xcodebuild -version` → 26.0.1 (17A400) | Blocking for R1–R3, task 8 — **user action: install Xcode 27 beta** |
| 1 | No Core Spotlight or App Intents integration exists in the codebase | repo-wide search for `CoreSpotlight`, `CSSearchable*`, `AppIntent` returns zero hits (confirmed 2026-07-23) | Blocking — Spike A has nothing to build on yet |
| 2 | No fixture corpus exists for retrieval evaluation | no `≥250 entries / ≥8 months / ≥40 gold questions` fixture set found anywhere in the repo | Blocking — REQ-IDX-010's recall@5 gate cannot be measured without one |
| 3 | Journaling Suggestions entitlement not requested | no evidence of a filed request; `REQ-CAP-009` requires filing "in week 1" | Time-sensitive — Apple review lead time is unknown and must be measured |
| 4 | PCC / Small Business Program eligibility unconfirmed | no evidence of enrollment or application in the repo or given context | Blocking — Phase 2's Z1 routing has no fallback if PCC access is denied |
| 5 | `DEC-002` (system-search visibility) is unresolved | flagged P0-blocking in the source document itself, §6.3 and §15 | Blocking — the entire retrieval architecture (§6) depends on the answer |

## Requirements

### R1. Resolve `DEC-002` (Spike C) — can Spotlight donation be hidden from system-wide search?
Work the test sequence in `technology/11-verification-queue.md` V1. The leading
hypothesis (`technology/03-spotlight-retrieval.md` §8) is a **named index** —
`CSSearchableIndex(name: "memento-entries")` instead of `.default()` — being
app-scoped and invisible to system Spotlight while remaining reachable by
`SpotlightSearchTool`, likely via its `configuration.sources` parameter. Test
order: (1) enumerate `SpotlightSearchTool.Configuration.sources` cases in the
SDK, (2) donate to a named index and confirm items do **not** appear in system
Spotlight **on a real device — not the simulator, system Spotlight behavior
differs**, (3) confirm `SpotlightSearchTool` still retrieves from it, (4) check
Data Protection / device-lock gating of the index, (5) check
`CSSearchableItemAttributeSet` for an exclude-from-system-UI attribute.
The verdict MUST also cover App Intents' `IndexedEntity` donation path
(`REQ-IDX-002`, spec 016; `REQ-SYS-002`, spec 020): entity-schema donations feed
the same semantic index and raise the same visibility question — one verdict for
both donation paths, not two investigations.
**Acceptance:** a written verdict — "hidden" (cite the API), "partially hidden"
(cite the caveat), or "not hidden" (triggers `REQ-IDX-006`'s default-excluded
opt-in posture and activates `REQ-IDX-007`'s SwiftData-query fallback tool as Plan
B) — checked into this spec's Current State before Phase 1 begins, and mirrored
into `technology/11-verification-queue.md` V1.

### R2. Spike A — Spotlight donation + retrieval quality
Build a throwaway prototype: donate the fixture corpus (R4) to Core Spotlight,
attach a `SpotlightSearchTool`-equipped session, run it against the ≥40 gold
questions.
**Acceptance:** recall@5 measured and recorded, compared against the `REQ-IDX-010`
bar (≥ 0.85). Pass/fail recorded in this spec, not just felt-sense judgment.

### R3. Spike B — reflection quality, on-device vs. PCC vs. current Gemini
Generate a weekly-reflection-shaped output for the same entry set three ways: AFM3
on-device, AFM3 via PCC, and the current Gemini 2.5 Flash implementation (as a
baseline). Blind-rate the outputs. The PCC arm SHOULD exercise all three
reasoning levels (`.light`/`.moderate`/`.deep` — `technology/02` §5) since the
level choice feeds the routing table too, and Apple's explicit guidance is
"choose models and reasoning levels based on data, not vibes — the updated
on-device model may surprise you." Use the `fm` CLI / Python SDK
(`technology/01` §10) for fast offline iteration over the fixture corpus rather
than building a throwaway harness app; structure the comparison as an
`Evaluations`-framework dataset from day one so it seeds spec 022's harness
instead of being discarded.
**Acceptance:** a written comparison with a recommendation on default Z0/Z1
routing **and reasoning level** for weekly reflection, feeding `REQ-INT-003`'s
routing table in spec 017.

### R4. Fixture corpus — DONE (2026-07-23)
Build a corpus of ≥ 250 synthetic journal entries spanning ≥ 8 months, plus a
hand-authored gold question set of ≥ 40 queries with known correct entries. The
corpus MUST deliberately include (per `technology/09-ui-swift6-testing.md` §7,
"Fixture corpus"):
- **sparse periods** (a week with two mundane entries) — so spec 022 can test
  that `hasNothingToSay` fires (`REQ-INT-013`);
- **emotionally heavy content** (grief, illness, conflict, self-critical
  language) — so guardrail refusal rate is measurable before launch
  (`technology/01` §11: journaling content disproportionately trips safety
  guardrails, and a refusal on the user's own entry must be a designed state);
- **adversarial prompts** ("what should I do?", "am I depressed?") — so persona
  adherence (`REQ-SUR-002`) is testable from day one.
**Acceptance:** corpus and question set checked into the repo (location TBD by the
implementing session — e.g. a `Fixtures/` target) with all three deliberate
content classes present, reusable by Spike A, by spec 016's ongoing recall@5
gate, and by spec 022's evaluation harness.

**Result:** 262 entries across 9 monthly files
(`Fixtures/corpus/entries-YYYY-MM.json`, 2025-11 through 2026-07, exceeds the
≥250/≥8-month bar), persona "J" with 10 narrative arcs (see
`Fixtures/README.md`), 45 gold questions (`Fixtures/gold/questions.json`,
exceeds ≥40) spanning temporal/person/event/synthesis/pattern/honesty
categories. Class distribution: 228 ordinary (87%, comfortably over the 60%
restraint-gate floor), 21 anchor, 10 heavy (guardrail refusal-rate content),
3 sparse-week (hasNothingToSay content) — all three deliberate content classes
present. Honesty-scrub verified: zero brother/Dario mentions before the
2026-03-08 reopening anchor. `Fixtures/validate_corpus.py` runs structural
validation (counts, unique IDs, vocab compliance, month coverage, honesty
scrub, gold-ID referential integrity) and materializes the 4 pattern-derived
gold questions (overcast-Monday mood, hardest weeks, bad-sleep periods, spring
running frequency) into `gold/questions.resolved.json` — all four resolved to
non-trivial match sets (10–16 entries each). All checks pass.

**Gap found and closed 2026-07-24:** `Fixtures/gold/adversarial.json` — named
in `Fixtures/README.md`'s own layout and required by this R's third deliberate
content class ("adversarial prompts... so persona adherence is testable from
day one") — had never actually been authored; the heavy/sparse classes made it
into the corpus but the prompt file itself was missing. Caught during spec
022's Requirements review (its `PersonaGate` cites the file). Now authored: 20
prompts (9 advice / 6 diagnosis / 5 crisis), each grounded in real corpus
arcs (all 12 referenced entry IDs validated against the corpus) with an
`expectedBehavior` rubric per prompt matching PersonaGate's three thresholds
(no-advice ≥98%, no-diagnosis 100%, crisis-routing 100%).

### R5. File entitlement and program applications
File: (a) App Store Small Business Program enrollment, (b) Private Cloud
Compute access request. (c) The Journaling Suggestions entitlement, previously
assumed to need a similar filing, turned out on research not to — see below.
**Acceptance:** (a) and (b) filed, with the filing date and any stated review
lead time recorded in this spec. This is a scheduling dependency for Phases
2–4, not merely an implementation detail — filing late risks blocking later
phases on Apple's review clock, not on our own work.

**Researched 2026-07-23** (via Apple Developer documentation + forum search —
🟡 confidence throughout; Apple's docs site didn't render fetchable body
content for one page, noted below where that applies). This replaces the
prior "unverified process, unknown lead time" state for all three items with
concrete process detail — two are real filings to make, one turned out to be
a non-issue:

**(a) App Store Small Business Program — eligibility confirmed, low-risk to
start immediately.**
- Eligibility: ≤$1,000,000 USD in App Store proceeds in the prior calendar
  year (proceeds = sales net of Apple's commission/taxes), **or** new to the
  App Store — Memento qualifies either way pre-launch.
- Requirements to enroll: be the Account Holder (not just a team member) of
  the Apple Developer Program membership; accept the current Paid Apps
  Agreement (Schedule 2) in App Store Connect; disclose any Associated
  Developer Accounts (>50% ownership or decision-making overlap with other
  developer accounts — presumed none for this solo project, confirm at
  filing time).
- Process: `developer.apple.com/app-store/small-business-program/enroll/` —
  Apple's own marketing copy calls this "free and takes about five minutes,"
  but Apple's program terms elsewhere describe an **approval** step, with
  commission-rate changes taking effect "fifteen (15) days after the end of
  the fiscal calendar month in which enrollment is approved" — i.e. the form
  itself may be short, but "enrolled" and "approved" aren't necessarily the
  same instant. Not fully reconciled from documentation alone.
- **Action:** file this first, immediately — it's free, low-effort, and is
  the eligibility gate for (b). No reason to wait on anything else in this
  spec.

**(b) Private Cloud Compute access — the genuinely gated, unknown-lead-time
filing.**
- Eligibility (all three required): enrolled in the Small Business Program;
  fewer than 2,000,000 first-time downloads across all apps (trivially true
  pre-launch); the PCC entitlement itself assigned to the developer account.
- This does **not** happen automatically upon SBP enrollment — it is a
  separate, explicit request: `developer.apple.com/contact/request/private-cloud-compute/`.
- No lead time is stated anywhere in Apple's own documentation — this is a
  real, confirmed gap (not merely something this research pass didn't get
  to), consistent with `technology/10-monetization-and-privacy.md`'s original
  flag that this is the architecture's least-controllable dependency.
- Testing via TestFlight/ad hoc distribution doesn't count against the 2M
  download threshold. If downloads later exceed 2M, or SBP enrollment lapses,
  Apple gives a 6-month migration window before cutting off access — worth
  noting as an ongoing operational constraint (`DEC-006`-adjacent), not just
  a one-time filing concern.
- **Action:** file immediately after (a) is confirmed enrolled — this is the
  step to start the "unknown lead time" clock on as early as possible.

**(c) Journaling Suggestions entitlement — corrected: likely does NOT need a
filing at all.**
Spec 018 Task 2 and the source tech doc both previously flagged this as
needing "a request to Apple with review lead time," treated as urgent as the
PCC filing. Research didn't support that: `com.apple.developer.journal.allow`
appears to be a **standard Xcode-addable capability** (Signing & Capabilities
→ "+ Capability" → Journal), available since Xcode 15.1 beta / iOS 17.2, with
no discoverable request-form URL or approval-queue reference anywhere in
Apple's docs or developer-forum discussion — unlike PCC, which has an
explicit, named request endpoint. 🟡 not ✅ because Apple's entitlement
reference page is a JS-rendered SPA that didn't yield fetchable body text
through available tooling, so this rests on converging indirect evidence
(search-result summaries, absence of a request-form link, general developer
community usage since iOS 17.2) rather than a direct doc citation.
- **Action — cheap, do this whenever spec 018 is picked up, not urgently
  now:** open Xcode → target → Signing & Capabilities → search "Journal". If
  addable directly, this confirms the correction and the item drops off the
  filing-dependency list entirely; if Xcode instead surfaces a request/
  approval prompt, that's the actual process to follow (and would mean this
  research pass's conclusion was wrong — re-flag as 🔴 and file properly).
Full detail and sourcing: `specs/reference/technology/08-context-frameworks.md`
§2 and `specs/reference/technology/10-monetization-and-privacy.md` §1 (both
updated 2026-07-23 with this same research).

### R6. Re-audit legacy specs for 2.0 relevance
Specs 003, 004, and 010 are already marked obsolete (superseded by 015, 016, and
019 respectively). Specs 002 (store metadata), 007 (offline resilience), 008
(accessibility), 009 (launch experience), 011 (test foundation), and 012
(post-launch backlog) were not automatically re-scoped — audit each against the
2.0 architecture and either confirm it still applies as-is, needs amendment, or
should also be marked obsolete/merged into a 013–022 spec.
**Acceptance:** a decision recorded per spec (001/005/006 are `done` and are
explicitly out of scope for this re-audit — see Out of Scope) in `ROADMAP.md`'s
pre-2.0 status board or in this spec's Tasks output.

### R7. Deletion manifest sign-off
Confirm the deletion manifest in the source document (§14.1) against the actual
repo inventory of `supabase/` (32 migrations as of 2026-07-23 — re-count at
execution time, this number moves; 6 edge functions: `chat`, `chat-feedback`,
`generate-insights`, `new-user-insights`, `summarize-chat`, `sync-embedding`;
plus `_shared/`) so spec 015's Phase 1 execution has an accurate, current
checklist rather than a generic one.
**Acceptance:** manifest cross-checked; any repo-specific item not covered by the
source document's generic table (e.g. `chat-feedback`, `new-user-insights`) is
called out explicitly.

## Legacy spec disposition (resolved 2026-07-23, ahead of formal execution)

Task 6 (re-audit specs 002/007/008/009/011/012 for 2.0 relevance) was resolved out
of band, before this spec's formal execution, at the user's request. Decisions
made and already reflected in each spec's front-matter/body:

| Spec | Disposition | Rationale |
|---|---|---|
| 002 | `paused` | ASC-submission work has nothing to submit until a 2.0/interim build exists; its completed hygiene work is generic and stays valid. |
| 007 | `obsolete` → 015 | 2.0's SwiftData-authoritative + CloudKit-replication model (`REQ-PLAT-003`, `REQ-DATA-001`) is a stronger offline guarantee than 007's Supabase-era sync-queue design. |
| 008 | `obsolete` → merged into 020 | Duplicates `REQ-A11Y-*` already owned by spec 020; its findings will churn once spec 019 rebuilds the Views it audited. |
| 009 | kept, R2 rescoped | R1/R3/R4 (theme-aware launch, single glass system, no `NavigationView`) are backend-independent and unaffected. R2 (consolidate 3 auth failsafes) is built around a Supabase session-fetch race that spec 015's Sign-in-with-Apple-only auth may remove outright — re-check against 015 before executing R2. |
| 011 | kept, R4 rescoped | R1–R3 target `EncryptionService`/`SecurityService`/`AuthViewModel`, explicitly unaffected by the rewrite (`CONSTITUTION.md` §2 Security). R4 targets `JournalService`, being replaced wholesale by spec 015 — its acceptance criteria move to the new SwiftData layer. |
| 012 | item-level: #5 and #7 removed, #9 promoted to spec 019, #10 reworded, #6/#8 cross-referenced | #5 (streaming) and #7 (Deno test harness) are absorbed/deleted by the rewrite; #9 (prompt-injection hardening) is materially more urgent once Ask does tool-calling (spec 019) than as a "post-launch" item; #10's last-write-wins premise is replaced by CloudKit's native conflict resolution (spec 015). |

## Out of Scope

- Actually deleting `supabase/` — that's spec 015 (Phase 1), gated on this spec's
  Spike A passing and `DEC-002` resolving.
- Building the real (non-throwaway) Spotlight donation pipeline — spec 016.
- Re-auditing specs 001, 005, 006 — they're `done` and describe completed,
  still-accurate work; nothing here should reopen them.
- Resolving `DEC-001`, `DEC-003`, `DEC-004`, `DEC-005`, `DEC-006`, `DEC-007` — each
  belongs to a later spec per `ROADMAP.md`'s decision table.

## Tasks
- [ ] 1. Investigate and resolve `DEC-002` (R1); record verdict and cite sources.
- [x] 2. Build the fixture corpus and gold question set (R4). **Done
      2026-07-23** — 262 entries, 45 gold questions, `validate_corpus.py`
      passing.
- [ ] 3. Run Spike A (Spotlight donation + retrieval) and record recall@5 (R2).
- [ ] 4. Run Spike B (reflection quality comparison) and record the routing
      recommendation (R3).
- [ ] 5. File Small Business Program / PCC verification and the Journaling
      Suggestions entitlement request; record filing dates (R5). **Research
      done 2026-07-23** (see R5 above for full detail, sourcing, and links):
      Small Business Program is a self-serve enrollment (eligibility
      confirmed: ≤$1M prior-year proceeds or new developer) — file
      immediately, it's low-cost and unblocks PCC; PCC access is a genuinely
      separate, gated request with no stated lead time
      (`developer.apple.com/contact/request/private-cloud-compute/`) — file
      right after SBP; Journaling Suggestions turned out to likely **not**
      need a filing at all (standard Xcode capability, not a gated
      entitlement — 🟡, verify with one click in Xcode's Signing &
      Capabilities). **The actual filings/submissions still require the
      account holder's Apple Developer login — not agent-executable; the two
      real filings (a, b) remain open user actions.**
- [x] 6. Re-audit specs 002, 007, 008, 009, 011, 012 for 2.0 relevance; record a
      decision for each (R6). **Resolved 2026-07-23, ahead of formal execution of
      this spec's other tasks — see "Legacy spec disposition" below.**
- [x] 7. Cross-check the deletion manifest against the actual `supabase/` inventory
      (R7). **Done 2026-07-23.** Verified inventory: **32 migrations**
      (`supabase/migrations/*.sql`), **6 edge functions** (`chat`,
      `chat-feedback`, `generate-insights`, `new-user-insights`,
      `summarize-chat`, `sync-embedding`) + `_shared/` (auth/cors/rate-limit
      helpers + 3 deno test files) + a functions `README.md`, `config.toml`,
      and an **empty `snippets/` dir** (delete with the tree). Total ~512KB.
      Repo-specific items NOT in the source doc's generic §14.1 table, called
      out per the acceptance criterion: `chat-feedback` (thumbs feedback CRUD —
      2.0 replacement is local `Reflection.userRating`/`Turn` feedback, spec
      015/022), `new-user-insights` (onboarding keyword matcher, no LLM — no
      2.0 replacement needed; onboarding personalization stays local, spec 023),
      `summarize-chat` (→ Z0 summarize-to-entry via `IntelligenceService`,
      spec 019 PRES-046), `sync-embedding` (→ nothing; embeddings cease to
      exist), `_shared/` rate-limiter (→ `QuotaGovernor`, spec 017). Also in
      deletion scope beyond `supabase/` itself: the deno job in
      `ios-tests.yml`, both deploy workflows, the "Assert Release endpoint"
      build phase, `SUPABASE_*` xcconfig/Info.plist keys, and the
      `supabase-swift` SPM dependency (see the implementation plan and spec
      015 tasks).
- [ ] 8. Xcode 27 beta API-surface sweep: work the P2 items in
      `technology/11-verification-queue.md` that block Phases 1–2 (V9–V13, V15,
      V16, V19, V25) — per the queue's own guidance, "most of P2 resolves in an
      afternoon of autocomplete and header reading." Update the queue file's
      markers (🔴 → ✅) as items resolve; later-phase items (V17–V18, V20–V24,
      V26–V28) stay owned by the specs whose `tech_refs` cite them.

## Verification
- [ ] `DEC-002` has a written, sourced verdict in this file (not just "TBD").
- [x] Fixture corpus exists, is ≥ 250 entries / ≥ 8 months, and the gold question
      set is ≥ 40 queries with known-correct entries recorded. ✅ 2026-07-23 —
      262 entries / 9 months, 45 gold questions,
      `python3 Fixtures/validate_corpus.py` passes all checks.
- [ ] Spike A's recall@5 number is recorded and compared explicitly against the
      0.85 bar from `REQ-IDX-010`.
- [ ] Spike B's comparison and routing recommendation are recorded.
- [ ] Both entitlement/program filings show a recorded filing date.
- [x] Every one of specs 002/007/008/009/011/012 has an explicit re-audit decision
      recorded (not silently skipped). ✅ 2026-07-23 — see "Legacy spec disposition"
      below; independently verified against each target spec's actual content.

## Regression Guards
This spec does no code changes, so `CONSTITUTION.md`'s DO-NOT-REGRESS list is not
at risk here. The one guard that matters: **do not let Phase 1 (spec 015) start
before this spec's gate — Spike A pass and `DEC-002` resolved — is met.** Starting
the deletion early is the specific failure mode this spec exists to prevent (P7,
"delete before you add" only after the replacement is measured, not before).
