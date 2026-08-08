# ROADMAP — Memento App Store Readiness

Review date: **2026-07-13** · branch `sync/upstream-main` · workflow in `specs/README.md`.

**2026-07-23:** Memento 2.0 (see
`specs/reference/memento-2.0-architecture-spec.md`) supersedes the pre-2.0
architecture in priority. See "2.0 Rewrite — Phase Plan" immediately below. The
"Status board" / "Launch gates" sections further down describe the *pre-2.0* app.
Of specs 001–012: 001/005/006 are done (untouched, accurate history); 002 is
paused; 007/008/010 are obsolete (superseded by the 2.0 rewrite — see their own
rows in the Status board below); 003/004 are likewise obsolete; 009/011 remain
active but partially rescoped; 012 is parked. The "Launch gates"/"Recommended
execution order" sections below were written for the pre-2.0 app and have **not**
been re-derived for this new state — treat their sequencing as historical, and
follow the Status board table's per-spec status instead.

## 2.0 Rewrite — Phase Plan

Status board for specs 013–023, mapped to the phase plan in
`specs/reference/memento-2.0-architecture-spec.md` §14.2. The order specs are
listed in each phase's row is the recommended execution order (usually numeric —
Phase 1 is the exception: 014 → 023 → 015); phases themselves are mostly
sequential (each phase's exit gate unlocks the next), per the source document.

| Phase | Specs | Gate | Status |
|---|---|---|---|
| 0 — De-risk | [013](013-phase-0-derisking-and-migration-prep.md) | Spike A passes, Spike C (`DEC-002`) resolved | in-progress, **Gate α pending device evidence** (see spec 013's "Gate α status" table) — Xcode 27 beta installed and verified; API sweep (task 8) done, 15 V-queue items resolved; Spike A simulator floor recorded (no Plan-B trigger) and Spike C's retrievability half positive; the two gate-closing runs (system-UI visibility check + full-stack recall@5) need a physical iOS 27 device with Apple Intelligence; entitlement/SBP filings (R5) researched, still unfiled (user action) |
| 1 — Subtract | [014](014-privacy-model-and-trust-boundary.md), [023](023-no-account-experience.md), [015](015-data-layer-swiftdata-cloudkit.md) | Accounts removed (023, before 015 so the UI no longer calls auth when the backend dies); Supabase tier deleted; SwiftData+Spotlight data layer live | in-progress — 023 R1–R6 done and verified (R7 manual walkthrough outstanding); 014 and 015 Requirements written; 015 implementation blocked on Xcode 27 beta for the target bump, `supabase/` deletion gated on Phase 0's exit criteria |
| 2 — Intelligence boundary | [016](016-indexing-retrieval-core-spotlight.md), [017](017-intelligence-boundary-and-prompt-architecture.md) | Entry reflection (Z0) working end to end | in-progress (spec-writing only) — 016 Requirements written with both `DEC-002` branches; 017 Requirements written; implementation gated on spec 013's Spike A/C and Xcode 27 beta |
| 3 — Surfaces | [018](018-capture-and-voice-output.md), [019](019-surfaces.md) | Weekly → Patterns → Ask shipped in that order | in-progress (spec-writing only) — 018 and 019 Requirements written; implementation gated on Phases 1–2 landing and the Xcode 27 toolchain |
| 4 — Voice & system | [020](020-system-integration-and-accessibility.md) | TTS + App Intents/widgets live | in-progress (spec-writing only) — 020 Requirements written; `DEC-005` (Watch) open, `REQ-SYS-002` gated on `DEC-002` |
| 5 — Study | [021](021-monetization-and-store-compliance.md), [022](022-evaluation-and-quality-study.md) | Re-baselined 30-day quality study running | in-progress (spec-writing only) — 021 and 022 Requirements written; `DEC-001`/`DEC-004` and the LLM-as-judge decision open |

Nothing in Phase 0 deletes anything — it is pure de-risking (entitlement filings,
fixture corpus, spikes, `DEC-002` resolution). Phase 1 is where `supabase/` actually
gets deleted, gated on Phase 0's exit criteria per the source document ("if Spike A
fails, activate `REQ-IDX-007` Plan B and re-scope" — i.e. don't delete the backend
until the replacement is proven).

Open decisions (`DEC-nnn`) from the source document, and the spec responsible for
resolving each:

| Decision | Owning spec | Priority | Technology reference |
|---|---|---|---|
| `DEC-002` — can Spotlight donation be hidden from system search? | 013 | **P0, blocking** | `technology/11-verification-queue.md` V1; `technology/03-spotlight-retrieval.md` §8 |
| `DEC-006` — does HealthKit context enter Z1 prompts? | 015 | P1 | `technology/11-verification-queue.md` V7; `technology/08-context-frameworks.md` §2–§3 |
| `DEC-007` — audio retention default | 015 | P2 | `technology/05-data-swiftdata-cloudkit.md` §4 |
| `DEC-003` — remote prompt manifest in 2.0 or 2.1? | 017 | P2 | `technology/01-foundation-models.md` §12 |
| `DEC-005` — Watch companion in 2.0 or 2.1? | 020 | P2 | `technology/07-app-intents-and-surfaces.md` |
| `DEC-001` — ship on non-Apple-Intelligence devices? | 021 | P1 | `technology/10-monetization-and-privacy.md` §1 |
| `DEC-004` — final pricing and trial length | 021 | P1 | `technology/10-monetization-and-privacy.md` §7 |

**2.0 constitutional gate ladder (partial, landed 2026-08-02).** The SDK-free,
decision-free CI gates that can run before the Swift rewrite exist and are wired
in `.github/workflows/spec-gates.yml` (green on the current tree; each verified
to fail on a planted violation):

- Single `FoundationModels` importer — spec 017 R1 / P3 (blocking)
- REQ-POS-001 forbidden-phrase lint — spec 014 R3 (blocking)
- SpeakabilityLinter pattern engine + selftest — spec 018 R9 (blocking)
- Dependency allowlist — spec 021 R6 (report-only until spec 015 decommission)
- Fixture-corpus validation + resolved-gold drift guard — spec 013 R4 / 016 R8 (blocking)

These are engine/CI halves; the Swift implementations they guard still depend on
Gate α + the toolchain/device. Making them *required* checks is a branch-
protection setting (`docs/BRANCH_PROTECTION_SETUP.md`). No `DEC-nnn` was resolved:
015/020 explicitly hold DEC-006/007/005 open for a human decision.

Spec 013's re-audit of whether specs 002, 007, 008, 009, 011, 012 (below) still
apply once 2.0 lands is **resolved** — see spec 013's "Legacy spec disposition"
section and the Status board rows immediately below, which already reflect it.

**Front-end decisions resolved 2026-07-23** (recorded in spec
[023](023-no-account-experience.md) and the preservation contract's ATTACH map —
`specs/reference/frontend-preservation-contract.md`): **no accounts at all**
(supersedes the source doc's Sign-in-with-Apple replacement); app lock
default-on-**skippable** with friction; forgot-PIN recovery via
**device-passcode fallback**; Patterns mounts as a **third pill tab**
(ATTACH-03); Settings Account + Data & Privacy **merged into one "Your Data"
section**. The entire existing front-end is under non-regression protection via
`PRES-nnn` IDs in that contract.

---

## Status board (pre-2.0 app)

| Spec | Title | Tier | Effort | Depends on | Status |
|------|-------|------|--------|------------|--------|
| [001](001-repo-hygiene-and-secrets-audit.md) | Repo Hygiene and Secrets Audit | P0 | 1 | — | ✅ done (2026-07-13) |
| [002](002-store-metadata-compliance.md) | Store Metadata and Binary Compliance | P0 | 1–2 | 001 | ⏸ paused (2026-07-23) — hygiene work done and still valid; ASC submission on hold until a 2.0/interim build exists |
| [003](003-database-baseline-and-account-deletion.md) | Database Baseline and Account Deletion | P0 | 2 | — | ⛔️ obsolete (2026-07-23) — superseded by 2.0 rewrite, see [015](015-data-layer-swiftdata-cloudkit.md) |
| [004](004-edge-function-security-and-cost.md) | Edge Function Security and LLM Cost Controls | P1 | 2 | 003 | ⛔️ obsolete (2026-07-23) — superseded by 2.0 rewrite, see [016](016-indexing-retrieval-core-spotlight.md) |
| [005](005-release-logging-privacy.md) | Release Logging Privacy | P1 | 1 | — | ✅ done (2026-07-14) |
| [006](006-ci-and-build-config-integrity.md) | CI and Build Configuration Integrity | P1 | 1–2 | 003 | ✅ done (2026-07-14) — CI-live checks are user actions |
| [007](007-offline-resilience.md) | Offline Resilience | P2 | 2 | — | ⛔️ obsolete (2026-07-23) — superseded by 2.0 rewrite, see [015](015-data-layer-swiftdata-cloudkit.md) |
| [008](008-dynamic-type-and-accessibility.md) | Dynamic Type and Accessibility Completion | P2 | 2 | — | ⛔️ obsolete (2026-07-23) — merged into [020](020-system-integration-and-accessibility.md) |
| [009](009-launch-experience-and-ui-consistency.md) | Launch Experience and UI System Consistency | P2 | 1–2 | — | not-started — R2 rescoped pending [015](015-data-layer-swiftdata-cloudkit.md), R1/R3/R4 unaffected |
| [010](010-chat-reliability.md) | Chat Reliability and Error Contract | P2 | 1 | 004 | ⛔️ obsolete (2026-07-23) — superseded by 2.0 rewrite, see [019](019-surfaces.md) |
| [011](011-test-foundation.md) | Test Foundation for Security-Critical Paths | P2 | 2–3 | 006 | not-started — R4 rescoped pending [015](015-data-layer-swiftdata-cloudkit.md), R1–R3 unaffected |
| [012](012-post-launch-backlog.md) | Post-Launch Backlog (Parking Lot) | P3 | n/a | — | parked |

Effort is in implementation sessions.

## Launch gates

**Describes the pre-2.0 app and is historical.** Superseded in priority by the
"2.0 Rewrite — Phase Plan" section above. Of the specs this table names, only
009 and 011 are still active (both partially rescoped — see the Status board
above); 002 is paused; 003/004/007/008/010 are obsolete. This table and the
"Recommended execution order" below are kept as a record of the pre-2.0 plan,
not as current guidance — do not execute obsolete specs' Tasks because they
appear as a "requires done" entry here.

| Gate | Unlocks | Requires done (pre-2.0 plan; several now obsolete/paused) |
|------|---------|---------------|
| **Gate 1** | First TestFlight upload (internal testing) | 001, 002 ⏸, 003 ⛔️ |
| **Gate 2** | External beta / App Store submission | 004 ⛔️, 005, 006 |
| **Gate 3** | 1.0 quality bar (work during beta window) | 007 ⛔️, 008 ⛔️, 009, 010 ⛔️, 011 |
| Post-launch | — | harvest 012 |

Rationale highlights:
- **003 is Gate 1**, not just "backend work": broken account deletion is an App Store
  rejection (guideline 5.1.1(v)), and you want the schema reproducible *before* beta
  data exists.
- **004 before external testers**: unauthenticated service-role endpoint + unlimited
  LLM spend is tolerable for you alone, not for a public beta link.
- ~~007–011 are parallelizable during the beta feedback window~~ — of that range,
  only 009 and 011 are still active; 007, 008, 010 are obsolete (2026-07-23).

**Note (2026-07-14):** 006 and (uncommitted) 004 work landed before 003 was started,
ahead of the dependency graph above. 003's repo-side work (migration reconciliation,
`delete_user()` fix) is now done too, so the ordering gap has mostly closed — but
003 still isn't formally `done` (its live-prod verification steps are pending), so
006/004 are shipping on the assumption 003's local-only fixes hold once verified
against prod. Gate 1 itself is still not unlocked: it needs 001✅, 002 (blocked on
user: Apple PLA), and 003 (blocked on user: `db diff --linked` + e2e test).

## Dependency graph (historical — pre-2.0 plan)

```
001 ──► 002                      (hygiene before store-surface edits)     [002 now paused]
003 ──► 004 ──► 010              (schema baseline → function hardening → error contract)  [003, 004, 010 now obsolete]
003 ──► 006 ──► 011              (honest replay → honest CI gates → tests ratchet)  [003 obsolete; 006 done; 011 still active]
005, 007, 008, 009 — independent  [007, 008 now obsolete; 005 done; 009 still active]
```

## Recommended execution order (historical — pre-2.0 plan, solo dev)

This sequence assumed shipping the pre-2.0 app; it's kept for history, not as
live guidance — see the 2026-07-23 note at the top of this file. If picking up
work outside the 2.0 rewrite, only 009 and 011 (both rescoped) are still
executable from this list.

1. ~~**001 → 002 → 003** — then archive + upload to TestFlight (**Gate 1**), start
   internal testing while continuing.~~
2. ~~**004 → 005 → 006** — then invite external beta testers (**Gate 2**), and prepare
   the App Store submission (ASC metadata checklist lives in spec 002).~~
3. ~~**During beta**: 009 (quick wins, launch feel) → 007 (offline — biggest UX payoff)
   → 010 → 008 → 011, adjusting to beta feedback. (**Gate 3**)~~ — only 009 and 011
   remain executable here.
4. ~~Submit 1.0 for review. Post-launch, harvest 012.~~

Total estimated effort to Gate 2: **8–10 sessions**. To 1.0: **~17–20 sessions**.
(Historical estimate; no longer the operative plan — see `ROADMAP.md`'s "2.0
Rewrite — Phase Plan" for current sequencing and effort.)

## Standing references

- Architecture baseline + non-regression list: `specs/CONSTITUTION.md`
- Tier definitions, workflow protocol, spec template: `specs/README.md`
- Memento 2.0 source-of-truth (REQ-/DEC- IDs cited by specs 013–022):
  `specs/reference/memento-2.0-architecture-spec.md`
- Apple-framework API reference library (`tech_refs:` cited by specs 013–022):
  `specs/reference/technology/00-INDEX.md`
- Superseded: `TESTFLIGHT_READINESS.md` (Oct 2025 snapshot — historical only)
