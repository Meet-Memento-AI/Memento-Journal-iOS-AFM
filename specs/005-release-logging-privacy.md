---
id: 005
title: Release Logging Privacy
tier: P1
status: not-started
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

## Tasks

- [ ] 1. Inventory: generate the full list of `print(` sites grouped by file
      (script it; save output in this spec or a scratch note).
- [ ] 2. Sweep ViewModels + Services first (PII lives here): delete or migrate to
      `AppLogger`; strip PII per R2. (R1/R2)
- [ ] 3. Sweep app entry (`MeetMementoApp.swift`, `LaunchLoadingView.swift`) —
      the body-evaluation print at `:40` just dies. (R1)
- [ ] 4. Sweep Components/Views (mostly deletions). (R1)
- [ ] 5. Convert existing `#if DEBUG print` blocks to `AppLogger` for consistency. (R1)
- [ ] 6. Add the SwiftLint custom rule; run `swiftlint` locally to confirm zero
      violations. (R3)
- [ ] 7. Release-build console audit (see Verification).

## Verification

- [ ] `grep -rn "print(" MeetMemento/ --include="*.swift" | grep -v "#Preview" | wc -l` → 0.
- [ ] `swiftlint --strict` on the repo → passes, and deliberately adding a `print(` makes
      it fail.
- [ ] Build Release configuration to a device/simulator, exercise launch → sign-in →
      journal → chat, and watch Console.app filtered to the app process: **no app log
      lines containing an email, UUID-looking user id, or entry text**.
- [ ] App still builds and behaves identically (logging is side-effect-free).

## Regression Guards

- Don't delete error-**handling** while deleting error-**printing** — every removed
  `print` in a `catch` must leave the user-facing error path (`errorMessage` /
  `.alert`) intact. Spot-check ChatViewModel/EntryViewModel error alerts still fire.
- `AppLogger` remains DEBUG-gated (CONSTITUTION §3 reference implementation) — don't
  "fix" it into always-on logging.
