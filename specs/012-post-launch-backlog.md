---
id: 012
title: Post-Launch Backlog (Parking Lot)
tier: P3
status: not-started
effort: n/a — harvest items into new numbered specs when picked up
depends_on: []
findings: [no-localization, autologout-timestamp-userdefaults, uitests-skipped-in-ci, color-contrast-audit, streaming-responses, structured-logging-platform, deno-handler-test-harness, self-hosted-runner-migration, prompt-injection-hardening-round2]
---

# 012 — Post-Launch Backlog (Parking Lot)

## Why

Deliberately deferred items. **Nothing here blocks TestFlight, App Store review, or
1.0 quality.** Each entry records enough context to be harvested into a proper
numbered spec (013+, using the template in `specs/README.md`) when its time comes.
Keeping them here prevents them from bloating the launch-critical specs — and
prevents them from being forgotten.

## Items

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

### 5. Chat response streaming
Responses currently arrive whole (typewriter effect is client-side animation).
True streaming (SSE from the edge function) would cut perceived latency
substantially. Touches `chat/index.ts`, `ChatService`, `ChatViewModel`,
`AIOutputComponent`. Consider after 010's error contract is stable.

### 6. Structured logging / crash reporting platform
`AppLogger` (DEBUG-gated) is the 1.0 answer (spec 005). Post-launch, consider
`os.Logger` categories + a crash reporter (e.g. Sentry) for beta triage — weigh
against the app's privacy positioning before adding any third-party SDK (would also
require PrivacyInfo.xcprivacy updates).

### 7. Deno handler-level test harness
Specs 004/010 add targeted function tests (limiter, auth, error contract). A general
harness for HTTP-handler testing (mock Supabase client, JWT fixtures) remains unbuilt;
`chat/lib_test.ts`'s pure-helper pattern is the seed.

### 8. Self-hosted runner strategy
CI is coupled to personal self-hosted runners (spec 006 documents + de-personalizes
but doesn't migrate). Decide long-term: GitHub-hosted (cost) vs hardening the
self-hosted setup (bus factor). Revisit when CI minutes/budget are clearer.

### 9. Prompt-injection hardening, round 2
Reviewed 2026-07-13 as LOW: journal content is self-authored (self-targeted injection
only), output is JSON-schema-constrained, and citation ids are filtered to the
retrieved set. If shared/collaborative content ever ships, re-review immediately —
that changes the threat model completely.

### 10. Multi-device sync conflict resolution
Spec 007 ships last-write-wins. If multi-device usage becomes real, revisit with
proper conflict handling (updated_at vectors or CRDT-lite). Also consider iCloud
backup semantics for the local pending-sync queue.

### 11. Launch-screen content design
The 2026-07 merge adopted upstream's spinner + "Starting…" launch loading view over
the previous centered-logo design (noted during merge review). Revisit with beta
feedback — a logo-based loading state may feel more branded. Pure design decision.

## Workflow

To pick up an item: create `specs/0NN-<name>.md` from the README template, move the
item's context there, delete it from this file, and add the new spec to
`ROADMAP.md`'s board.
