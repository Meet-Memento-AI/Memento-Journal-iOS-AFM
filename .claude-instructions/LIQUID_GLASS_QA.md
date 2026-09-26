# Liquid Glass: Setup and QA

## 1. Tab bar and tab style

- **TabView** uses `.tabViewStyle(.sidebarAdaptable)` (iOS 18+).
- On **iOS 26+**, `.tabBarMinimizeBehavior(.onScrollDown)` is applied so the tab bar can minimize on scroll; this is the only place that uses this modifier.
- Tab bar uses the system’s glass/material look.
- **Tab content identity:** Each tab root has a stable `.id(0)` (Journal) and `.id(1)` (Insights) so SwiftUI keeps the same instances when switching and avoids teardown/recreate flicker.
- **Tab bar tint:** A **single** tint (no `selectedTab` dependency) is used: `colorScheme == .dark ? .white : PrimaryScale.primary900` so the bar does not visibly change color when switching tabs (avoids tint flash).
- **Tab transition:** `.animation(.easeInOut(duration: 0.18), value: selectedTab)` gives a short cross-fade instead of a snap; 0.18s is used in all three TabView branches.

## 2. Navigation bar (Liquid Glass)

- **Unified bar style:** All main tab roots and pushed screens that show a nav bar use:
  - `.toolbarBackground(.visible, for: .navigationBar)`
  - `.toolbarBackground(.ultraThinMaterial, for: .navigationBar)`
- Applied on: **JournalView**, **InsightsView**, **AIChatView**, **SettingsView**, **AddEntryView**, and any other pushed destination that displays a navigation bar.
- **InsightsView** keeps toolbar items in white for contrast on the purple background; other screens use theme foreground or equivalent.

## 3. Tab switch snappiness and flash avoidance

- Tab selection uses **0.18s** easeInOut: `.animation(.easeInOut(duration: 0.18), value: selectedTab)` on the TabView for a smooth cross-fade. The binding is `$selectedTab` (no custom Transaction wrapper).
- **Programmatic tab changes** (e.g. from Insights “save” or AI Chat) set `selectedTab` via the environment binding; the same 0.18s animation applies once.
- **InsightsView first frame:** Sync “restore from cache” and `showInstantContent()` run in `.onAppear` so the first paint when switching to Insights already shows cached content; `.task` is used only for async work (`loadEntriesIfNeeded`, `loadForCurrentMonth`). This avoids a flash from async state updates after the first frame.

## 4. QA checklist (regression)

After any change that touches tabs or nav bars, run through:

1. **Tab switching**
   - Switch between Journal and Insights repeatedly.
   - Confirm no visible flash; smooth 0.18s cross-fade; toolbar and content update without “slow adaptation” or style jump.

2. **Push / pop**
   - From Journal: push Add Entry, Settings, AI Chat; pop back.
   - From Insights: push Add Entry, AI Chat, Settings; pop back.
   - Confirm the nav bar does not “flash” or change style when pushing or popping; bar stays consistent (visible + ultraThinMaterial).

3. **iOS 26 only: tab bar minimize**
   - On a device/simulator running iOS 26, scroll in Journal and Insights.
   - Confirm tab bar minimize-on-scroll (if enabled) feels consistent and not jarring; note any screens or scroll contexts where it misbehaves.

4. **Logging**
   - If anything still feels slow or inconsistent, log: **screen**, **action** (tab switch / push / pop / scroll), and **iOS version** for follow-up.

## 5. Files involved

| Area              | Files |
|-------------------|--------|
| Tab style / animation | `withMemento/ContentView.swift` |
| Journal root bar  | `withMemento/Views/Journal/JournalView.swift` |
| Insights root bar| `withMemento/Views/Insights/InsightsView.swift` |
| Pushed screens    | `withMemento/Views/Journal/AddEntryView.swift`, `withMemento/Views/AI-Chat/AIChatView.swift`, `withMemento/Views/Settings/SettingsView.swift` |

No changes to InsightsService or API; this is UI/QA only.
