---
id: 007
title: Offline Resilience
tier: P2
status: not-started
effort: 2 sessions
depends_on: []
findings: [no-network-monitoring, no-offline-ux, no-local-first-writes]
---

# 007 — Offline Resilience

## Why

A journaling app gets used on planes, subways, and in bed with bad wifi. Today there is
**zero connectivity awareness**: no `NWPathMonitor`, no offline state, no queued
writes. Losing a journal entry to a network error is the single worst UX failure this
app can have — it destroys exactly the trust a private journal depends on. Currently a
persistent offline state just surfaces as repeated generic errors (services retry with
backoff, then give up). Gate 3 (fix during beta window — beta feedback will surface
this fast).

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | No `NWPathMonitor` / reachability anywhere; `grep -ri "NWPathMonitor\|Reachability\|isConnected\|offline"` over app code → nothing. | codebase-wide | HIGH |
| 2 | Entry saves are network-first; a failed save surfaces an error but nothing guarantees the draft survives (no durable queue). | `MeetMemento/Services/JournalService.swift` (retry loop `:45`), `EntryViewModel` | HIGH |
| 3 | Chat/insights spinners have no "you're offline" affordance — failures read as the app being broken. | `AIChatView`, `InsightsView` | MEDIUM |
| 4 | An unused/underused local persistence layer already exists to build on. | `MeetMemento/Services/LocalJournalStorage.swift` | leverage |

## Requirements

### R1. Connectivity service
**Acceptance:** a small `NetworkMonitor` service (NWPathMonitor-backed,
`@Published isConnected`, injected via environment) reflects airplane-mode toggles
within ~2s; unit-testable behind a protocol.

### R2. Journal writes are local-first
**Acceptance:** saving an entry **always** succeeds locally first (via
`LocalJournalStorage`), then syncs to Supabase; with no network the entry appears in
the journal list (with a subtle pending-sync indicator) and survives app relaunch;
on reconnect it syncs automatically and the indicator clears; conflicts resolve
last-write-wins (documented).

### R3. Honest offline UX for network-only features
**Acceptance:** chat and insights show a clear "Memento needs a connection for this"
state (reusing the existing empty-state component style) instead of spinners/error
alerts when `isConnected == false`; the journal (read + write) remains fully usable
offline.

### R4. Offline banner
**Acceptance:** a dismissible, non-blocking banner/pill appears when offline (matching
the design system), disappears on reconnect.

## Out of Scope

- Full bidirectional sync engine / multi-device conflict resolution — last-write-wins
  is 1.0 policy (revisit in spec 012 if multi-device becomes real).
- Offline queueing for chat messages (chat is inherently online — R3 covers it).
- Embedding sync retry hardening (server side) → covered by 004's pipeline checks.

## Tasks

- [ ] 1. Build `NetworkMonitor` service + environment injection. (R1)
- [ ] 2. Audit `LocalJournalStorage` — extend to a durable pending-sync queue
      (entry payload + op type + timestamp). (R2)
- [ ] 3. Rework entry save path in `EntryViewModel`/`JournalService`: local write →
      UI update → async sync → mark synced / leave queued. (R2)
- [ ] 4. Reconnect sync trigger (monitor callback + app-foreground). (R2)
- [ ] 5. Pending-sync indicator on `JournalCard` + entry detail. (R2)
- [ ] 6. Offline states for chat + insights views. (R3)
- [ ] 7. Offline banner component. (R4)
- [ ] 8. Unit tests: queue survives encode/decode round-trip; monitor protocol mock
      drives view-model state. (feeds spec 011's coverage)

## Verification

Manual script (simulator: toggle network via Settings, or device airplane mode):
- [ ] Airplane mode → write entry → appears in list with pending indicator → kill app →
      relaunch (still offline) → entry still there.
- [ ] Reconnect → indicator clears within seconds → entry visible in Supabase dashboard.
- [ ] Offline: open chat → "needs connection" state (no spinner-forever, no error alert
      storm); open insights → same; journal list scrolls and reads normally.
- [ ] Banner appears offline, clears on reconnect.
- [ ] Unit tests green.

## Regression Guards

- Entry **encryption** (CONSTITUTION §2): locally queued entries must go through the
  same `EncryptionService` path as synced ones — never store plaintext in the queue
  that wouldn't be stored plaintext today.
- Existing retry-with-backoff in `JournalService`/`ChatService` still applies to the
  sync step (don't replace one resilience layer while removing the other).
- No regression to launch time — the monitor must not block startup.
