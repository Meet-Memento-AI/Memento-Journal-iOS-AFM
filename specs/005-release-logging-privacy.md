---
id: 005
title: Release Logging Privacy
tier: P1
status: done (2026-07-14)
effort: 1 session
depends_on: []
findings: [unguarded-print-statements, pii-in-logs, applogger-underused]
---

# 005 — Release Logging Privacy

## Why

~208 `print()` statements exist; roughly **90 are unguarded** and execute in release
builds, several logging **user ids and emails** to the device console
(readable via Console.app / sysdiagnose by anyone with the device). For a
privacy-positioned journaling app this is both a real PII leak and a bad look in App
Review. The fix is mechanical because the right tool already exists:
`AppLogger` (`MeetMemento/Utils/Logger.swift`) is DEBUG-gated. Blocks **Gate 2**.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | `AuthViewModel` — 15 unguarded prints including PII: `Session Restored: \(session.user.id)` and similar at `:135,:293,:336`. | `MeetMemento/ViewModels/AuthViewModel.swift` | HIGH |
| 2 | `UserService` logs user **emails** unguarded at `:62,:90,:111`. | `MeetMemento/Services/UserService.swift` | HIGH |
| 3 | Unguarded prints in security-sensitive code: `SecurityService.swift:111,139`, `EncryptionService.swift:55-177`. | those files | MEDIUM |
| 4 | `MeetMementoApp.swift:40` — `let _ = { print("🔴 MeetMementoApp body evaluated") }()` runs on **every body evaluation** in release; also `:109` watchdog print; `LaunchLoadingView.swift:52` failsafe print. | app entry | MEDIUM |
| 5 | ~20 Components/Views files with unguarded prints (`DrawerMenuView`, `TopNavHeader`, `AIChatFooter`, `ThemeTag`, `ListeningPanel`, …). | `MeetMemento/Components/`, `Views/` | LOW |
| 6 | Good pattern exists but is inconsistently applied: some files wrap in `#if DEBUG` (`ChatService.swift:109-112`, `JournalService.swift:45-48`); `AppLogger` in `MeetMemento/Utils/Logger.swift` is the canonical tool. | reference implementations | — |

## Requirements

### R1. Zero raw `print()` in the shipping app target
**Acceptance:** `grep -rn "print(" MeetMemento/ --include="*.swift"` returns zero hits
in shipping code (test targets and `#Preview` bodies excluded); everything worth
keeping is migrated to `AppLogger` calls; worthless debug noise is deleted outright
(prefer deletion — most of the 208 are stale).

### R2. No PII in any log statement at any level
**Acceptance:** no log call includes user id, email, token, PIN-related values, or
journal/chat content. Where a correlation handle is genuinely needed, log a truncated
hash (e.g. first 8 chars of SHA256(user id)). Grep audit for `user.id`, `email`,
`session.` inside logging calls comes back clean.

### R3. Regression prevented by lint
**Acceptance:** `.swiftlint.yml` gains a `custom_rules` entry (or enables
`no_print` equivalent) that flags `print(` in `MeetMemento/` as an **error**;
CI's SwiftLint step fails on new prints. (If SwiftLint remains advisory in CI, that
gap is spec 006's — the rule still lands here.)

## Out of Scope

- Making SwiftLint blocking in CI → **spec 006**.
- Structured logging/analytics platform (os.Logger categories, remote crash
  reporting) → **spec 012** if desired; `AppLogger` is sufficient for 1.0.

## Implementation notes (2026-07-13/14)

- **Inventory**: 189 `print(` sites across ~40 files at start (the "~208/~90 unguarded"
  estimate included tests). Migrated **all** to `AppLogger.log(...)` (bulk perl transform:
  `print(` → `AppLogger.log(`, collapsing 11 `#if DEBUG print #endif` wrappers since
  AppLogger is already DEBUG-gated). Only remaining `print` is AppLogger's own
  implementation (`Utils/Logger.swift:19`) — the single allowed sink.
- **PII stripped** (R2) — 6 log calls carried PII, all fixed:
  - `InsightsService` logged the **full request JSON payload** (journal entry content)
    and a **full user id** — both removed (the dead debug encode block + unused
    `currentUserId` deleted entirely).
  - `session.title` (chat/journal-derived) in 3 chat-history callbacks → generic message.
  - `entry.id` in EntryViewModel → removed.
  - Emails in `UserService` (3 sites) → removed (done in the first partial pass).
- **AuthViewModel** (user ids at :135/:293/:336), **UserService** (emails),
  **ChatViewModel** were migrated first (PII priority); `SecurityService` /
  `EncryptionService` swept via the bulk pass.
- **SupabaseService.swift**: spec 005 delegated deeper config-error surfacing to spec 006,
  but its 2 `print`s were migrated to `AppLogger` here so `swiftlint --strict` passes at
  this commit; spec 006 still does the assertionFailure/visible-error-state work around them.
- **SwiftLint guard** (R3): `custom_rules.no_print` added to `.swiftlint.yml` — flags
  `print(` as **error**, excludes `Utils/Logger.swift`. (Making the CI SwiftLint step
  *blocking* is spec 006.)

## Tasks

- [x] 1. Inventory generated (189 sites). (R1)
- [x] 2. ViewModels + Services swept, PII stripped. (R1/R2)
- [x] 3. App entry swept — `MeetMementoApp.swift` body-evaluation print deleted;
      `LaunchLoadingView` failsafe print migrated. (R1)
- [x] 4. Components/Views swept. (R1)
- [x] 5. `#if DEBUG print` blocks collapsed to `AppLogger`. (R1)
- [x] 6. SwiftLint `no_print` custom rule added. (`swiftlint` not installed locally —
      rule validated by inspection; CI runs it.) (R3)
- [ ] 7. Release-build Console.app PII audit — **user action** (needs a device/Console.app
      session; grep-level PII audit passed).

## Verification

- [x] `grep -rn "print(" MeetMemento/ --include="*.swift"` → 1 (only `Utils/Logger.swift`,
      the canonical sink). ✅
- [x] Grep PII audit: no `AppLogger.log` call contains `email`, full `user.id`/`currentUserId`,
      `session.title`, `jsonString`, token, or entry content. ✅
- [x] `xcodebuild … build` (Debug, iPhone 17 sim) → **BUILD SUCCEEDED** after the sweep. ✅
- [ ] `swiftlint --strict` — swiftlint not installed locally; runs in CI (spec 006 makes it
      blocking). Rule authored to fire on `print(` as error.
- [ ] Release Console.app audit (launch→sign-in→journal→chat, no PII lines) — **user action**.

## Regression Guards

- Don't delete error-**handling** while deleting error-**printing** — every removed
  `print` in a `catch` must leave the user-facing error path (`errorMessage` /
  `.alert`) intact. Spot-check ChatViewModel/EntryViewModel error alerts still fire.
- `AppLogger` remains DEBUG-gated (CONSTITUTION §3 reference implementation) — don't
  "fix" it into always-on logging.
