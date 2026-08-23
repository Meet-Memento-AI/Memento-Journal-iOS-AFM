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
| 0 — De-risk | [013](013-phase-0-derisking-and-migration-prep.md) | Spike A passes, Spike C (`DEC-002`) resolved | **DEC-002 written 2026-08-19: Plan B** (no named-index source in SpotlightSearchTool). Gate α device numbers still pending — harnesses in Spike A/C tests |
| 1 — Subtract | [014](014-privacy-model-and-trust-boundary.md), [023](023-no-account-experience.md), [015](015-data-layer-swiftdata-cloudkit.md) | Accounts removed; SwiftData+CloudKit data layer | in-progress — 023 R1–R6 done (R7 manual walkthrough outstanding); 015 schema + CloudKit private config + five-store deletion + DEC-006/007 landed; `supabase/` already gone |
| 2 — Intelligence boundary | [016](016-indexing-retrieval-core-spotlight.md), [017](017-intelligence-boundary-and-prompt-architecture.md) | Entry reflection (Z0) working end to end | **Branch B** (DEC-002). Ask pipeline + PromptRegistry `ask@14` shipping; spec 039 adds `chat-light@4`; DEC-003 = bundled prompts only |
| 3 — Surfaces | [018](018-capture-and-voice-output.md), [019](019-surfaces.md) | Weekly → Patterns → Ask shipped in that order | in-progress — SpeechAnalyzer capture engine; Weekly/Patterns UI; Ask already live |
| 4 — Voice & system | [020](020-system-integration-and-accessibility.md) | TTS + App Intents/widgets live | in-progress — four App Intents + lock-redacted widget view; DEC-005 = Watch via those intents; WatchKit host in `MeetMementoWatch/` |
| 5 — Study | [021](021-monetization-and-store-compliance.md), [022](022-evaluation-and-quality-study.md) | Re-baselined 30-day quality study running | in-progress — DEC-001/004 written; 022 eval harness still the study owner |
| **S — Ship** | [`docs/app-store/`](../docs/app-store/), [025](025-ci-online-ios-build-gates.md) | **Gate S — Submit for Review**: every item in [`docs/app-store/00-readiness-checklist.md`](../docs/app-store/00-readiness-checklist.md) closed with evidence; merge CI proves online-testable iOS build specs (not on-device FM generation) | in-progress (2026-08-07) — library compiled against Apple's current docs; four CI gates live; **three P0 defects found live in production or the binary**, see below; **025 done (2026-08-10)** — `ios-tests.yml` replaced by `ios-build-online.yml` + optional `ios-device-eval.yml` (CI-live / branch-protection rename is a user action) |
| 6 — Experience (added 2026-08-18) | [026](026-behavioral-safety-guardrails.md), [027](027-navigation-redesign.md), [028](028-conversational-narration.md), [029](029-performance-and-speech-excellence.md), [037](037-conversational-recall-experience.md), [039](039-reply-channels-and-phatic-generation.md) | Narration is a reliable multi-turn conversation inside Chat, at budget; Ask recall feels like a notebook beside them; simple turns are fast | in-progress — 027 shipped with the nav redesign; 028 and 029 landed their first passes 2026-08-17/18; 037 ask@14 notebook path; **039 complete** (`chat-light@4`, always-Open, ConversationalMove). These post-date the original phase plan and were previously untracked here |
| 7 — Voice (added 2026-08-18) | [030](030-neural-tts-model-assets.md), [031](031-neural-synthesis-engine.md), [032](032-tts-streaming-and-latency.md), [033](033-neural-voice-catalog.md), [035](035-spoken-form-formatter.md), [036](036-neural-voice-verification.md); [034](034-full-duplex-conversation-audio.md) off the critical path | **Gate V — Voice**: 036's release gates pass on physical devices, with a proxy-verified zero-egress artifact archived | in-progress — model vendored; DEC-008/009/010/011/012 written (008/009 freeze after V29/V30 device traces); SpokenFormFormatter + conversation AEC + mask skip-if-missing; Gate V artifact still on-device |

**Gate S — Ship (added 2026-08-07).** Store readiness is not a spec, because it
is mostly *not* code: it is App Store Connect fields, Apple-side filings with
review queues, and published web pages. It lives in `docs/app-store/` and is
tracked here so it is visible alongside the engineering phases.
[`docs/app-store/00-readiness-checklist.md`](../docs/app-store/00-readiness-checklist.md)
is the single pre-Submit page; it defines **Gate T (TestFlight external)**,
**Gate S (Submit)**, and **Gate L (Live)**.

Compiling it surfaced three defects that were live, not theoretical:

1. **The Support URL returns HTTP 404 in production** — the exact Guideline 1.5
   reason Apple rejected v1.0 in November 2025, still unfixed. The corrected
   page *was* committed, but GitHub Pages serves from a **different repository
   and branch** (`sebmendo1/MeetMemento` @ `Memento-v1.1`), so it never
   published.
2. **The published privacy policy still names OpenAI, Google, and Supabase** —
   third-party AI and a backend the app no longer uses. Same root cause, and it
   directly contradicts the "Data Not Collected" label target.
3. **`PrivacyInfo.xcprivacy` declared `SystemBootTime` (`35F9.1`) for an API the
   app never calls** — fixed 2026-08-07, now guarded by CI.

Four gates were added to `spec-gates.yml` alongside the existing ladder:
`check_privacy_manifest.sh` (bidirectional — under- *and* over-declaration),
`check_store_metadata.sh` (export compliance, purpose-string quality, and a
build-number floor, since `1.0(2)` was consumed by the rejected upload),
`check_archive_hygiene.sh` (which immediately caught the `Config/*.xcconfig`
entries missing from the synchronized-group exception set — the same regression
class as spec 002 evidence row 7), and `check_asc_metadata.sh` (App Store copy
held to `REQ-POS-001`, field limits, no pricing, no clinical framing). Each was
verified to fail on a planted violation.

Nothing in Phase 0 deletes anything — it is pure de-risking (entitlement filings,
fixture corpus, spikes, `DEC-002` resolution). Phase 1 is where `supabase/` actually
gets deleted, gated on Phase 0's exit criteria per the source document ("if Spike A
fails, activate `REQ-IDX-007` Plan B and re-scope" — i.e. don't delete the backend
until the replacement is proven).

Open decisions (`DEC-nnn`) from the source document, and the spec responsible for
resolving each:

| Decision | Owning spec | Priority | Verdict (2026-08-19) |
|---|---|---|---|
| `DEC-002` — can Spotlight donation be hidden from system search? | 013 | **P0** | **Plan B.** SDK: `SpotlightSearchTool` has no named-index source (`CoreSpotlightSource` has no index-name). Default `excludedFromIndex = true` / indexing opt-in off. Retrieval = `EntryRetriever` (`REQ-IDX-007`). Gate α device run still records system-UI + recall@5; it cannot reverse this default without a hiding API. |
| `DEC-006` — does HealthKit context enter Z1 prompts? | 015 | P1 | **Never.** Coarse Z0 snapshots may live on the entry; they are stripped from every Z1 prompt. |
| `DEC-007` — audio retention default | 015 | P2 | **Discard after transcription.** Setting still offers 30-day / keep-forever. |
| `DEC-003` — remote prompt manifest in 2.0 or 2.1? | 017 | P2 | **2.0 = bundled only.** `PromptRegistry` remains Swift constants. No signed remote manifest. |
| `DEC-005` — Watch companion in 2.0 or 2.1? | 020 | P2 | **2.0 via the four App Intents on-wrist.** Dedicated WatchKit host lives in `MeetMementoWatch/` (not on the iOS merge scheme). |
| `DEC-001` — ship on non-Apple-Intelligence devices? | 021 | P1 | **Yes, Reduced-tier capture-only, no paywall.** Store copy must not claim Apple Intelligence is required. |
| `DEC-004` — final pricing and trial length | 021 | P1 | **Keep $9.99/mo and $79/yr.** Trial length unchanged until App Store Connect is retuned. |
| `DEC-008` — ANE placement with dynamic shapes, or fixed-shape buckets? | 031 | P1 | **Lock `.cpuAndNeuralEngine`, GPU excluded, dynamic shapes.** V29 device traces still to be archived; code already matches this lock. |
| `DEC-009` — is the provisional voice roster the shipping roster, under AEC? | 033 | P1 | **Four-voice catalog ships (F1/F2/M1/M3).** Freeze under AEC after V30 audition; picker already replaced the system-voice list (`DEC-011`). |
| `DEC-010` — model-weight attribution placement | 030 | ✅ | Settings → About → Acknowledgments |
| `DEC-011` — neural catalog vs system-voice picker | 033 | ✅ | Neural catalog replaces it |
| `DEC-012` — bundle vs download model | 030 | ✅ | Bundle |

**Device pack remaining (does not reopen the written verdicts):** 013 Gate α system-UI + recall@5 on a physical iOS 27 + Apple Intelligence phone; 037/028/029/023 R7 manual; V29 traces; V30 AEC; 036 Gate V artifact. Harnesses exist; numbers are not invented.

**Duplicate spec id 024** was split: Liquid Glass keeps [024](024-liquid-glass-authentic-adoption.md); experience-profile is [038](038-experience-profile-and-theme-estimation.md).

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
Gate α device evidence for *measured* recall, not for the written DEC-002
verdict (Plan B, 2026-08-19). Making them *required* checks is a branch-
protection setting (`docs/BRANCH_PROTECTION_SETUP.md`). DEC-001 through DEC-009
are written in the table above; 015/020 no longer hold 006/007/005 open.

**Online-vs-device CI (spec [025](025-ci-online-ios-build-gates.md), done
2026-08-10).** Merge workflows: `ios-build-online.yml` (check name
**iOS build (online)**), `security.yml`, `spec-gates.yml`. Optional
`ios-device-eval.yml` is never a required check. Operators must update branch
protection to replace any stale `iOS quality gates` required check with
`iOS build (online)`. Hosted-runner migration remains parked under spec 012 #8.

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
| [002](002-store-metadata-compliance.md) | Store Metadata and Binary Compliance | P0 | 1–2 | 001 | ⛔️ superseded (2026-08-07) — store-facing scope moved to [`docs/app-store/`](../docs/app-store/); the completed binary hygiene stays valid and is now guarded by CI |
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
- **App Store Connect submission and review readiness (Gate S): `docs/app-store/`**
  — start at `docs/app-store/00-readiness-checklist.md`. Supersedes spec 002's
  store-facing scope.
- Superseded: `TESTFLIGHT_READINESS.md` (Oct 2025 snapshot — historical only)
