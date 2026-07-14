---
id: 009
title: Launch Experience and UI System Consistency
tier: P2
status: not-started
effort: 1-2 sessions
depends_on: []
findings: [launch-white-flash-dark-mode, triple-startup-failsafe, dual-glass-systems, deprecated-navigationview]
---

# 009 — Launch Experience and UI System Consistency

## Why

First impressions and structural UI debt. Dark-mode users get a **white flash on every
cold start** (`LaunchLoadingView` hardcodes white while the rest of the app is
theme-aware). Startup correctness currently depends on **three independent, duplicated
failsafes** (3s watchdog, 6s view failsafe, 8s fetch timeout) that each hand-mutate
five `@Published` auth fields — it works, but any future auth change must be kept in
sync in three places (this fragility descends from the MEM-18 blank-screen bug).
And the 2026-07 upstream merge left **two parallel glass-effect systems** in the tree
with visibly different fallback behavior — `AddEntryView` uses both at once. Gate 3.

## Current State (evidence)

> Re-verify each row before starting work — line numbers rot. Update stale refs.

| # | Problem | Evidence | Severity |
|---|---------|----------|----------|
| 1 | `LaunchLoadingView` hardcodes `Color.white.ignoresSafeArea()`; app root elsewhere uses theme-aware `RootBackground` (`MeetMementoApp.swift:18`). Dark-mode cold start flashes white. | `MeetMemento/Views/LaunchLoadingView.swift:29` (approx; re-verify) | MEDIUM |
| 2 | Three failsafes race: 3s watchdog (`MeetMementoApp.swift:106-116`), 6s secondary (`LaunchLoadingView.swift:45-61`), 8s session-fetch timeout (`AuthViewModel.initializeAuth` `:106`). The first two duplicate verbatim the manual mutation of `isAuthenticated`/`hasCompletedOnboarding`/`authState`/`hasCheckedAuth`/`isInitializing`. | those three sites | MEDIUM (fragility) |
| 3 | Two glass systems: native `.glassEffect` inside `#if canImport(FoundationModels)` guards (11 files: `TopNavHeader`, `TopTabNav`, `SettingsView`, `AppearanceSettingsView`, `AboutSettingsView`, `DataUsageInfoView`, `ChatInputField`, `NarrateButton`, `ListeningPanel`, `ChatHistorySheet`, `AddEntryView`) vs `mementoGlassEffect` wrapper (8 files: `ContentView`, `NewEntryFAB`, `DrawerMenuView`, `ChatHistoryItem`, `EditAboutYourselfView`, `LearnAboutYourselfView`, `AddEntryView`). **`AddEntryView` uses both.** Wrapper's `.tint()`/`.interactive()` are documented no-ops (`GlassEffectCompat.swift:9-16`) → surfaces silently differ. | grep both APIs | MEDIUM |
| 4 | Deprecated `NavigationView` still in 2 files (target is iOS 17+; `NavigationStack` is the replacement). | `grep -rln "NavigationView" MeetMemento/` | LOW |

## Requirements

### R1. Theme-aware launch
**Acceptance:** cold start in dark mode shows a dark background end-to-end
(LaunchScreen.storyboard → LaunchLoadingView → root view) with no white frame;
light mode unchanged. Consider whether the DEBUG diagnostics overlay in
`LaunchLoadingView` should stay (it's `#if DEBUG` — fine — just make it theme-aware).

### R2. One startup failsafe
**Acceptance:** exactly one timeout path resolves a hung auth bootstrap, living in
`AuthViewModel` (e.g. a single `resolveAsUnauthenticated(reason:)` method); the
watchdog and view failsafe either call it or are deleted; no call site hand-mutates
the five auth fields; the MEM-18 scenario (slow/no network at launch) still resolves
to the welcome screen within a bounded time (~6–8s).

### R3. One glass system
**Acceptance:** a single API renders every glass surface. Recommended: keep the
`mementoGlassEffect` **name** as the app-wide API but upgrade
`GlassEffectCompat.swift` to internally branch — native
`.glassEffect(.regular.interactive(), in:)` on iOS 26+ (inside the `canImport` guard),
material fallback otherwise — honoring `tint`/`interactive` on the native path
instead of no-ops. Then migrate all 11 native-call files to the wrapper and delete
their per-file `#if canImport` scaffolding + `fallback*Background` duplicates.
Grep for `.glassEffect(` finds only `GlassEffectCompat.swift`.

### R4. No deprecated navigation containers
**Acceptance:** zero `NavigationView` in the app target; replaced with
`NavigationStack` (behavior verified on the affected screens).

## Out of Scope

- Launch *content* redesign (logo vs spinner debate — the 2026-07 merge chose
  upstream's spinner+"Starting…" layout; changing that is a product decision, note it
  for the beta feedback pile).
- Dynamic Type on these screens → **spec 008**.
- Any auth *logic* change beyond consolidating the failsafe (token refresh, session
  handling stay as-is).

## Tasks

- [ ] 1. Make `LaunchLoadingView` background theme-aware; verify against
      `LaunchScreen.storyboard` background for a seamless handoff. (R1)
- [ ] 2. Add `AuthViewModel.resolveAsUnauthenticated(reason:)`; route the 8s fetch
      timeout through it. (R2)
- [ ] 3. Reduce the three failsafes to one owner (keep the longest-stop watchdog if
      needed, but as a one-line call into the VM method); delete duplicated mutation
      blocks. (R2)
- [ ] 4. Upgrade `GlassEffectCompat` per R3 (native branch honors tint/interactive). (R3)
- [ ] 5. Migrate the 11 native-`.glassEffect` files to `mementoGlassEffect`; delete
      per-file fallbacks (`fallbackPillBackground`, `fallbackCardBackground`, etc.). (R3)
- [ ] 6. Visual regression pass on all glass surfaces, light+dark (they carry
      deliberate dark-mode fills from the July merge — preserve appearance). (R3)
- [ ] 7. Replace the 2 `NavigationView`s with `NavigationStack`. (R4)

## Verification

- [ ] Device/simulator in dark mode: cold launch screen-recording shows no white frame.
- [ ] Airplane-mode cold launch: app resolves to welcome/lock screen in ≤8s via the
      single failsafe (add a temporary log to prove which path fired, then remove it).
- [ ] `grep -rn "\.glassEffect(" MeetMemento/ --include="*.swift"` → only
      `GlassEffectCompat.swift`; `grep -rn "fallback.*Background" MeetMemento/` → 0.
- [ ] `grep -rln "NavigationView" MeetMemento/` → 0.
- [ ] Side-by-side screenshots (before/after) of: chat input pills, top nav, tab pill,
      settings cards, FAB, drawer, AddEntryView — light and dark — appearance preserved.
- [ ] Full test suite + a normal launch → journal → chat smoke run.

## Regression Guards

- **MEM-18** must not regress: the no-network cold start resolving past the loading
  screen is the exact bug the failsafes exist for — the airplane-mode verification
  above is mandatory, not optional.
- Dark-mode glass fills chosen in the 2026-07 merge (theme-aware frost layers) must
  survive the consolidation — the wrapper migration is a refactor, not a restyle.
- `@MainActor` discipline on `AuthViewModel` (CONSTITUTION §2) unchanged.
