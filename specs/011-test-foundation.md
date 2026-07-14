---
id: 011
title: Test Foundation for Security-Critical Paths
tier: P2
status: not-started
effort: 2-3 sessions
depends_on: [006]
findings: [zero-tests-outside-chat, security-code-untested, coverage-gate-ratchet]
---

# 011 — Test Foundation for Security-Critical Paths

## Why

The entire test suite is chat-only (~180 lines: `ChatViewModelTests`,
`ChatResponseDecodingTests`, a smoke test) plus 19 Deno tests on `chat/lib.ts`
helpers. The code most in need of tests has **zero**: `EncryptionService` (journal
encryption — a bug here silently corrupts user data), `SecurityService` (PIN/keychain),
`AuthViewModel` (the state machine three failsafes hang off), and `JournalService`
(the core CRUD). During beta, refactors from specs 007/009/010 will churn exactly these
areas — tests must exist before that churn compounds. Depends on 006 (gates made
honest first, so new tests ratchet a real floor). Gate 3.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | iOS tests: `ChatViewModelTests.swift` (83 L), `ChatResponseDecodingTests.swift` (55 L), `RegressionSmokeTests.swift` (8 L), `MockChatService.swift` (38 L). UITests exist but are `-skip-testing` in CI (`ios-tests.yml:71`). | `MeetMementoTests/` | — |
| 2 | Zero tests for `EncryptionService`, `SecurityService`, `AuthViewModel`, `JournalService`, `LocalJournalStorage`, onboarding VMs. | `MeetMemento/Services/`, `ViewModels/` | HIGH |
| 3 | Coverage gate 3% (spec 006 raises to the honest floor; this spec raises the floor itself). | `ios-tests.yml:84` | MEDIUM |
| 4 | Deno: only `chat/lib_test.ts` pure helpers; no handler/auth/limiter tests (004/010 add some). | `supabase/functions/` | MEDIUM |

## Requirements

### R1. Encryption round-trip is proven
**Acceptance:** unit tests cover: encrypt→decrypt round-trip preserves content
(multiple sizes incl. empty + emoji + long text); decrypt with wrong key fails
cleanly; salt persistence via a keychain mock/protocol; key derivation is
deterministic per (passphrase, salt). No test writes to the real keychain.

### R2. PIN/security service tested
**Acceptance:** tests cover PIN set/verify happy path, wrong-PIN rejection, and the
constant-time comparison function (correctness, not timing); auto-logout window logic
(14-day timestamp) covered with injected clock; keychain access behind a protocol so
tests run without entitlements.

### R3. Auth state machine tested
**Acceptance:** `AuthViewModel` tests drive: fresh-install → unauthenticated;
restored-session → authenticated; restored-needing-onboarding; bootstrap timeout →
the (post-spec-009) single failsafe resolves to unauthenticated. Supabase client
behind a mock/protocol seam.

### R4. Journal CRUD tested
**Acceptance:** `JournalService`/`EntryViewModel` create/update/delete happy paths +
error propagation, with mocked network; if spec 007 landed, pending-sync queue
round-trip included.

### R5. Coverage floor ratcheted
**Acceptance:** `MIN_COVERAGE` raised to the new honest measurement after R1–R4 land
(expect a meaningful jump; whatever the number is, it only goes up — comment in the
workflow says so, per 006).

## Out of Scope

- UITest re-enablement in CI (flaky on self-hosted runner — track in **spec 012**).
- Deno handler tests beyond what 004/010 added (park broader function-test harness in
  **spec 012**).
- Snapshot/visual regression testing (nice-to-have; 012).

## Tasks

- [ ] 1. Introduce protocol seams where needed (`KeychainStoring`, `SupabaseClienting`
      minimal surface, clock injection) — smallest change that makes the four targets
      testable; no architectural rewrite. (R1–R4)
- [ ] 2. `EncryptionServiceTests` per R1.
- [ ] 3. `SecurityServiceTests` per R2.
- [ ] 4. `AuthViewModelTests` per R3.
- [ ] 5. `JournalServiceTests` (+ queue tests if 007 landed) per R4.
- [ ] 6. Run coverage locally; set the new `MIN_COVERAGE`; confirm CI green. (R5)

## Verification

- [ ] `xcodebuild test -scheme MeetMemento -destination 'platform=iOS Simulator,name=iPhone 17'`
      → all green locally.
- [ ] CI `ios-tests.yml` green at the new gate on a PR branch.
- [ ] Mutation spot-check: intentionally break the constant-time compare (flip the
      accumulator) → a test fails; break decrypt (wrong key path) → a test fails.
      Revert.
- [ ] No test touches real keychain/network (run with network disabled once).

## Regression Guards

- Existing chat tests keep passing untouched.
- Protocol seams must not weaken production behavior: `SecurityService`'s
  keychain attributes (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) and the
  constant-time algorithm (CONSTITUTION §2) are asserted BY tests now — the seam
  wraps them, never replaces them.
- Coverage gate never decreases from this point (standing rule 6).
