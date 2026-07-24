# App Intents and System Surfaces

**Imports:** `import AppIntents`, `import WidgetKit`, `import ActivityKit`, `import BackgroundTasks`
**Role in Memento:** this is where the Apple-ecosystem strategy converts into defensibility. Each item is cheap individually; together they form a moat a minimalist competitor structurally will not build.

---

## 1. App Intents — the foundation

App Intents is no longer just "Shortcuts support." In iOS 27 it is the integration point for Siri, Spotlight, widgets, Controls, and the semantic index simultaneously. One correct implementation serves all of them.

✅ **VERIFIED** (Apple WWDC26 iOS guide): **SiriKit is deprecated in iOS 27.** No SiriKit code in Memento. Ever.

### Entity + intent schemas

✅ **VERIFIED** (Apple WWDC26 iOS guide):

> *Entity schemas contribute your app's content to the Spotlight semantic index, so Siri can surface it with attribution back to your app. Intent schemas let people take action on that content naturally with no specific phrases to define and no code changes needed as Siri's language understanding evolves.*

This is significant for Memento: **the same donation that powers `SpotlightSearchTool` retrieval also makes entries reachable by Siri.** One code path, two capabilities. See `03-spotlight-retrieval.md`.

🔴 Enumerate available domain schemas — there may or may not be a journaling domain. If there isn't, use the generic entity path.

### `AppEntity` and `IndexedEntity`

🟡 **LIKELY**

```swift
struct EntryEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Journal Entry")
    static var defaultQuery = EntryQuery()

    var id: UUID
    @Property(title: "Title")   var title: String
    @Property(title: "Date")    var createdAt: Date

    var displayRepresentation: DisplayRepresentation { ... }
}

struct EntryQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [EntryEntity] { ... }
    func suggestedEntities() async throws -> [EntryEntity] { ... }
}
```

Conforming to `IndexedEntity` is what donates to the Spotlight semantic index. **This is the same privacy question as DEC-002** — if entries are donated as indexed entities, do they surface in system search and in Siri results? Resolve before implementing.

### Intents to expose

| Intent | Parameters | Notes |
|---|---|---|
| **New entry** | optional spoken content | Dictate to Siri without opening the app — highest-value intent |
| **Read my weekly reflection** | — | Returns audio; pairs with `06-speech-and-audio.md` |
| **Ask my journal** | question | Returns a snippet |
| **Find entries about** | topic/date | Returns entity results |

Register via `AppShortcutsProvider` with natural phrases. Keep to the three-to-five actions users most want by voice — a bloated shortcut list degrades Siri's disambiguation.

### Per-intent privacy declarations

🔴 **UNVERIFIED but important.** Secondary sources report iOS 27 adds per-intent privacy manifest declarations to keep sensitive interactions on-device. For a journal, **every** intent should be declared on-device where the mechanism allows. Investigate and apply.

### View Annotations

🔴 **UNVERIFIED.** iOS 27 adds a View Annotations API mapping views to entities so people can reference on-screen content conversationally ("summarize this entry"). Potentially valuable for Memento; investigate after core surfaces ship.

### App Intents Testing framework

✅ **VERIFIED** (Apple WWDC26 iOS guide): validates the whole integration through real system pathways without UI automation. Use it — Siri integration is otherwise painful to test.

---

## 2. Widgets

🟡 **LIKELY** (WidgetKit, stable)

| Widget | Size | Content |
|---|---|---|
| Capture | small | One-tap to recording. The single most valuable widget. |
| Last observation | medium | The one line from the most recent reflection |
| Lock Screen capture | accessory | Fastest path to capture |

**Explicit prohibition:** no streak counters, no "days since last entry" framed as failure, no scores. NON-GOAL in the architecture spec. If a "days since" display cannot be phrased without shame, omit it entirely. The competitor differentiation here is *not* gamifying a private practice.

Widgets should never render journal content that would be visible on a locked screen without authentication. The "last observation" widget needs a redacted state — 🟡 use `privacySensitive()` in SwiftUI.

---

## 3. Control Center controls

🟡 **LIKELY** (`ControlWidget`, iOS 18+)

```swift
struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.memento.capture") {
            ControlWidgetButton(action: StartRecordingIntent()) { ... }
        }
    }
}
```

This is the **fastest path to capture on the device** and it costs almost nothing to build once the App Intent exists. For a voice journal where the whole value depends on capturing a thought before it evaporates, this is disproportionately valuable relative to effort.

---

## 4. Live Activities

🟡 **LIKELY** (ActivityKit)

During recording: elapsed time, waveform, stop action. **Dynamic Island presentation required** — recording is exactly the kind of ongoing, glanceable state the Dynamic Island exists for.

This also reinforces A4 in `06-speech-and-audio.md`: if a recording is running and the user leaves the app, the Live Activity is what tells them it's still going. Losing audio silently is the failure mode; the Live Activity is the mitigation.

---

## 5. Background tasks

🟡 **LIKELY** (`BackgroundTasks`)

```swift
import BackgroundTasks

BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.memento.weekly-reflection",
    using: nil
) { task in
    handleWeeklyReflection(task: task as! BGProcessingTask)
}

let request = BGProcessingTaskRequest(identifier: "com.memento.weekly-reflection")
request.requiresNetworkConnectivity = true   // PCC needs network
request.requiresExternalPower = false         // prefer true, don't require
```

**Requirements:**

- Weekly and monthly generation scheduled via `BGProcessingTask`
- `requiresNetworkConnectivity = true` when targeting PCC
- Failure retries with backoff
- **Fall back to foreground generation on next launch rather than silently skipping a week.** A missing Sunday reflection with no explanation is worse than a late one.
- Interacts with data protection class — see `05-data-swiftdata-cloudkit.md` §4. If the store is unreadable while locked, background generation cannot run and this whole design changes.

Background task scheduling is best-effort. Never promise the user an exact time; say "Sunday morning" and mean "some time Sunday."

---

## 6. watchOS

🟡 **LIKELY**

Scope: **capture only** in 2.1, not 2.0. On-watch transcription where supported, deferred transcription where not. Complication for one-tap capture. Sync via the shared CloudKit container.

Note from `02-private-cloud-compute.md`: **PCC is available on watchOS 27** ✅ VERIFIED, which means Watch-side reflection is technically possible later. `SpotlightSearchTool` is **not** available on watchOS ✅ VERIFIED, so retrieval-grounded features stay phone-side.

**Design the data layer now so the Watch app doesn't force a migration later.** That is the only 2.0 obligation.

---

## 7. Focus and Shortcuts

🟡 **LIKELY**

- **Focus filter** so a "Wind Down" or "Personal" Focus surfaces Memento's capture prompt. Cheap, and it puts the app in a genuinely appropriate moment.
- **Shortcuts actions** matching every App Intent — free once the intents exist. Small audience, disproportionately vocal, and precisely the audience that writes publicly about apps.

---

## 8. Notifications

`UserNotifications` for: daily reminder (opt-in, off by default), and "your weekly reflection is ready."

**Constraint from the architecture spec's NON-GOALs:** no notification-driven engagement loops. One optional daily reminder and one weekly ready-notification. Nothing else. No "you haven't written in 3 days," no re-engagement campaigns. A private journal that nags is a private journal that gets deleted.
