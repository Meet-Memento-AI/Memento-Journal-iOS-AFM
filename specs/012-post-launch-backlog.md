---
id: 012
title: Post-Launch Backlog (Parking Lot)
tier: P3
status: parked
effort: n/a — harvest items into new numbered specs when picked up
depends_on: []
findings: [no-localization, autologout-timestamp-userdefaults, uitests-skipped-in-ci, color-contrast-audit, structured-logging-platform, self-hosted-runner-migration, multi-device-sync-cloudkit]
---

# 012 — Post-Launch Backlog (Parking Lot)

## Why

Deliberately deferred items. **Nothing here blocks TestFlight, App Store review, or
1.0 quality.** Each entry records enough context to be harvested into a proper
numbered spec (013+, using the template in `specs/README.md`) when its time comes.
Keeping them here prevents them from bloating the launch-critical specs — and
prevents them from being forgotten.

## Items

**2026-07-23 note:** items below were re-audited against the Memento 2.0 rewrite
(`specs/reference/memento-2.0-architecture-spec.md`). #5 and #7 are removed
(absorbed/deleted, see strikethrough entries at the end of this list); #9 is
promoted out of the parking lot into spec 019; #10 is reworded; #6 and #8 gained
a 2.0 cross-reference. #1, #2, #4, #11 are unchanged — genuinely orthogonal to
the backend rewrite.

### 1. Localization
The app has **zero** localization infrastructure: no `Localizable.strings`/
`.xcstrings`, no `NSLocalizedString`/`String(localized:)` — every user-facing string
is hardcoded inline English (verified 2026-07-13). 1.0 ships **en-only** (decided).
When internationalizing: adopt String Catalogs (`.xcstrings`), sweep every view
(~29 view files + 74 components), and note that AI responses come from the backend —
system prompts would need locale awareness too. Effort: large (3+ sessions).

### 2. Auto-logout timestamp → Keychain
The 14-day auto-logout's last-activity timestamp lives in `UserDefaults`
(`SecurityService.swift:31-43`) — user-tamperable, unlike the Keychain-stored PIN.
Low risk (it gates a convenience logout, not data access). Move to Keychain or accept
and document. Effort: trivial; bundle with any future SecurityService work.

### 3. Re-enable UITests in CI
`MeetMementoUITests` are `-skip-testing` in CI (`ios-tests.yml:71`) due to
self-hosted-runner flakiness. Beta-period crash/regression coverage would benefit from
at least the launch smoke test running. Investigate simulator stability on the runner.

### 4. Color-contrast audit
Theme palette (light + dark) has not been audited against WCAG AA. Fix surface is the
token definitions in `MeetMemento/Resources/Theme.swift` (single point of change).
Flagged during spec 008's design; deferred because it may nudge brand colors.

### 5. ~~Chat response streaming~~ — removed 2026-07-23
Absorbed into the 2.0 rewrite as a hard requirement, not a backlog nice-to-have:
`REQ-INT-014` (spec [017](017-intelligence-boundary-and-prompt-architecture.md))
mandates snapshot streaming for chat/Ask.

### 6. Structured logging / crash reporting platform
`AppLogger` (DEBUG-gated) is the 1.0 answer (spec 005). Post-launch, consider
`os.Logger` categories + a crash reporter (e.g. Sentry) for beta triage — weigh
against the app's privacy positioning before adding any third-party SDK (would also
require PrivacyInfo.xcprivacy updates). **2026-07-23:** any such addition now also
requires going through spec [021](021-monetization-and-store-compliance.md)'s
`REQ-MON-005` dependency-allowlist governance (the 2.0 allowlist is currently just
RevenueCat).

### 7. ~~Deno handler-level test harness~~ — removed 2026-07-23
The Deno/edge-function runtime this would test is deleted entirely in Phase 1 of
the 2.0 rewrite (spec [015](015-data-layer-swiftdata-cloudkit.md)).

### 8. Self-hosted runner strategy
CI is coupled to personal self-hosted runners (spec 006 documents + de-personalizes
but doesn't migrate). Decide long-term: GitHub-hosted (cost) vs hardening the
self-hosted setup (bus factor). Revisit when CI minutes/budget are clearer.
**2026-07-23:** CI workflow *content* (not the runner strategy) needs updating once
`supabase/` is deleted in spec 015, since several jobs currently reference it.
**2026-08-10:** the *online-testable iOS build contract* (what merge CI must prove
without on-device FM generation) is harvested into spec
[025](025-ci-online-ios-build-gates.md). Item 8 remains parked only for the
cost/infra choice of GitHub-hosted vs self-hosted Macs once that contract exists.

### 9. Prompt-injection hardening, round 2 — promoted out of the parking lot, 2026-07-23
Reviewed 2026-07-13 as LOW: journal content is self-authored (self-targeted injection
only), output is JSON-schema-constrained, and citation ids are filtered to the
retrieved set. **No longer parked for post-launch:** Memento 2.0's Ask surface runs
a `SpotlightSearchTool` tool-calling loop over the user's own indexed data
(`REQ-SUR-002`/`REQ-SUR-003`, spec [019](019-surfaces.md)) — a materially different
and higher-stakes threat model than today's single-shot JSON-schema-constrained
chat. This item's adversarial-evaluation work moves into spec 019's Requirements
(and/or spec [022](022-evaluation-and-quality-study.md)'s adversarial persona-
adherence pass) rather than staying parked here.

### 10. Multi-device sync conflict resolution — reworded 2026-07-23
~~Spec 007 ships last-write-wins.~~ Spec 007 is obsolete (superseded by spec
[015](015-data-layer-swiftdata-cloudkit.md)); its custom last-write-wins queue
premise no longer applies. 2.0's CloudKit private-DB mirroring (`REQ-DATA-001`)
handles multi-device sync via CloudKit's native conflict resolution instead —
verify during spec 015 that CloudKit's native behavior is acceptable for this
product's needs; if not, revisit with proper conflict handling then. Lower
urgency than before (CloudKit's mechanism is a reasonable default, not an
acknowledged gap).

### 11. Launch-screen content design
The 2026-07 merge adopted upstream's spinner + "Starting…" launch loading view over
the previous centered-logo design (noted during merge review). Revisit with beta
feedback — a logo-based loading state may feel more branded. Pure design decision.

## Workflow

To pick up an item: create `specs/0NN-<name>.md` from the README template, move the
item's context there, delete it from this file, and add the new spec to
`ROADMAP.md`'s board.
