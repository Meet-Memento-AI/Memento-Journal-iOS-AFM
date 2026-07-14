# ROADMAP — Memento App Store Readiness

Review date: **2026-07-13** · branch `sync/upstream-main` · workflow in `specs/README.md`.

## Status board

| Spec | Title | Tier | Effort | Depends on | Status |
|------|-------|------|--------|------------|--------|
| [001](001-repo-hygiene-and-secrets-audit.md) | Repo Hygiene and Secrets Audit | P0 | 1 | — | ✅ done (2026-07-13) |
| [002](002-store-metadata-compliance.md) | Store Metadata and Binary Compliance | P0 | 1–2 | 001 | 🔶 in-progress — repo work done; blocked on user: accept Apple PLA → archive+validate; decide/verify support email |
| [003](003-database-baseline-and-account-deletion.md) | Database Baseline and Account Deletion | P0 | 2 | — | not-started |
| [004](004-edge-function-security-and-cost.md) | Edge Function Security and LLM Cost Controls | P1 | 2 | 003 | not-started |
| [005](005-release-logging-privacy.md) | Release Logging Privacy | P1 | 1 | — | ✅ done (2026-07-14) |
| [006](006-ci-and-build-config-integrity.md) | CI and Build Configuration Integrity | P1 | 1–2 | 003 | not-started |
| [007](007-offline-resilience.md) | Offline Resilience | P2 | 2 | — | not-started |
| [008](008-dynamic-type-and-accessibility.md) | Dynamic Type and Accessibility Completion | P2 | 2 | — | not-started |
| [009](009-launch-experience-and-ui-consistency.md) | Launch Experience and UI System Consistency | P2 | 1–2 | — | not-started |
| [010](010-chat-reliability.md) | Chat Reliability and Error Contract | P2 | 1 | 004 | not-started |
| [011](011-test-foundation.md) | Test Foundation for Security-Critical Paths | P2 | 2–3 | 006 | not-started |
| [012](012-post-launch-backlog.md) | Post-Launch Backlog (Parking Lot) | P3 | n/a | — | parked |

Effort is in implementation sessions.

## Launch gates

| Gate | Unlocks | Requires done |
|------|---------|---------------|
| **Gate 1** | First TestFlight upload (internal testing) | 001, 002, 003 |
| **Gate 2** | External beta / App Store submission | 004, 005, 006 |
| **Gate 3** | 1.0 quality bar (work during beta window) | 007, 008, 009, 010, 011 |
| Post-launch | — | harvest 012 |

Rationale highlights:
- **003 is Gate 1**, not just "backend work": broken account deletion is an App Store
  rejection (guideline 5.1.1(v)), and you want the schema reproducible *before* beta
  data exists.
- **004 before external testers**: unauthenticated service-role endpoint + unlimited
  LLM spend is tolerable for you alone, not for a public beta link.
- 007–011 are parallelizable during the beta feedback window (see dependencies).

## Dependency graph

```
001 ──► 002                      (hygiene before store-surface edits)
003 ──► 004 ──► 010              (schema baseline → function hardening → error contract)
003 ──► 006 ──► 011              (honest replay → honest CI gates → tests ratchet)
005, 007, 008, 009 — independent
```

## Recommended execution order (solo dev)

1. **001 → 002 → 003** — then archive + upload to TestFlight (**Gate 1**), start
   internal testing while continuing.
2. **004 → 005 → 006** — then invite external beta testers (**Gate 2**), and prepare
   the App Store submission (ASC metadata checklist lives in spec 002).
3. **During beta**: 009 (quick wins, launch feel) → 007 (offline — biggest UX payoff)
   → 010 → 008 → 011, adjusting to beta feedback. (**Gate 3**)
4. Submit 1.0 for review. Post-launch, harvest 012.

Total estimated effort to Gate 2: **8–10 sessions**. To 1.0: **~17–20 sessions**.

## Standing references

- Architecture baseline + non-regression list: `specs/CONSTITUTION.md`
- Tier definitions, workflow protocol, spec template: `specs/README.md`
- Superseded: `TESTFLIGHT_READINESS.md` (Oct 2025 snapshot — historical only)
