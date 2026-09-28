# MEM-18: Blank page on launch (root cause and fix)

## Symptom

After cold launch, some users saw a **blank frame** briefly (more often on slower networks). It was intermittent (~half the time in repro).

## Root cause

There was a **race between auth restoration and root view selection**:

1. `AuthViewModel` defaulted to `isAuthenticated == false`.
2. The app used `isInitializing` to decide whether to show `LaunchLoadingView` vs. the rest of the tree.
3. During the transition from “loading” to “session restored,” SwiftUI could **briefly** render the **logged-out** branch (`WelcomeView`) before switching to `ContentView` (or show an intermediate empty layout during teardown).
4. That **Welcome → main** transition (or layout swap) produced a **blank frame** in some timing/network conditions.

## Fix

Introduce an explicit **`hasCheckedAuth`** flag:

- **`false`** until `initializeAuth()` has fully completed (every branch: UI test bypass, inactivity logout, session restored, no session, error).
- **`true`** only after the final auth-related `@Published` updates for that run.

**`withMementoApp`** gates the root on **`!hasCheckedAuth`**: show `LaunchLoadingView` only until auth is known, then branch to `ContentView`, `OnboardingCoordinatorView`, or `WelcomeView` as before.

This separates **“auth outcome known”** from **`isInitializing`** (busy during network work inside `initializeAuth()`).

### Related code

- [`AuthViewModel.swift`](../withMemento/ViewModels/AuthViewModel.swift): `hasCheckedAuth`, `initializeAuth()` `defer { … }`, `bypassToMainApp()` / `skipToOnboardingForTesting()` set `hasCheckedAuth = true`.
- [`withMementoApp.swift`](../withMemento/withMementoApp.swift): root `if !authViewModel.hasCheckedAuth { LaunchLoadingView() … }`.

### UI tests

XCUITest uses `-UITesting` / `MEETMEMENTO_UI_TEST` so `initializeAuth()` signs out and clears state, then `defer` sets `hasCheckedAuth = true`. The app then shows Welcome with stable accessibility IDs.

### `signOut()`

Does **not** set `hasCheckedAuth` to `false`; the user is still in a “known” state (logged out).

## How to verify

1. Sign in and complete onboarding.
2. Force-quit and relaunch the app **several times**.
3. Expected: brief `LaunchLoadingView`, then `ContentView`, **no** blank flash and **no** Welcome flash.

## References

- PR: [Meet-Memento-AI/Memento-1.3#5](https://github.com/Meet-Memento-AI/Memento-1.3/pull/5)
