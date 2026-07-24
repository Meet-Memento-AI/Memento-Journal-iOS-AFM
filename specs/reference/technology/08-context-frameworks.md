# Context Frameworks — Journaling Suggestions, Health, Weather, Location

**Imports:** `import JournalingSuggestions`, `import HealthKit`, `import WeatherKit`, `import CoreLocation`, `import MapKit`
**Role in Memento:** the ingredients that turn "notices patterns" from a marketing claim into something structurally true.

---

## 1. Why this cluster matters strategically

Memento's competitive claim is that it finds real patterns in a life. A model reasoning over transcripts alone can only find patterns *in what the user chose to write*. These frameworks add the surrounding facts — sleep, movement, weather, place, what the user was doing — at close to zero privacy cost, because in every case the system brokers the data and the user grants it explicitly.

An austere minimalist competitor will not build this. It's the kind of depth that takes four frameworks and no server, and it's exactly where a design-led product should spend effort.

**But:** every one of these is a permission prompt, and every permission prompt is a moment where a user can decide your journal app is nosy. Ask late, ask in context, and make declining costless.

---

## 2. Journaling Suggestions — the underused one

🟡 **LIKELY** (iOS 17.2+ framework)

```swift
import JournalingSuggestions

JournalingSuggestionsPicker {
    Text("Add a suggestion")
} onCompletion: { suggestion in
    // Only what the user explicitly picked arrives here
}
```

### Why this is strategically significant

The system surfaces the user's own recent **workouts, photos, music, podcasts, significant locations, state-of-mind logs, and contacts interactions** as journaling prompts. The picker runs in the system's process. **Memento receives only what the user explicitly selects.**

That means rich personal context at **zero privacy cost to Memento** — no HealthKit read authorization, no Photos library access, no location permission. The system does the surfacing; the user does the selecting; the app receives a narrow, consented payload.

It is the highest ratio of contextual value to privacy surface available on the platform, and almost nobody in this category uses it.

### 🔴 SCHEDULING DEPENDENCY — act in week 1

The Journaling Suggestions entitlement **requires a request to Apple with review lead time**. This is not an implementation detail; it is a calendar dependency that can block Phase 4. File it in the same week as the PCC application.

🔴 Verify: current request process, expected lead time, and eligibility criteria.

### Rules

- A selected suggestion becomes an `Attachment` plus a **seeded prompt in the composer**.
- It MUST NOT auto-generate entry text on the user's behalf. The suggestion is a starting point for the user to write from, not a substitute for their writing. An app that writes your journal for you is not a journal.
- Suggestion content becomes searchable metadata on the entry — it improves retrieval as well as capture.

---

## 3. HealthKit — State of Mind

🟡 **LIKELY** (`HKStateOfMind`, iOS 18+)

### Reading

With explicit authorization, read coarse values only:

- Sleep duration, bucketed (not exact minutes)
- Workout occurred (boolean, not details)
- `HKStateOfMind` valence if the user logs mood in Health

Store as `Entry.healthContext`. Coarse by design — Memento does not need and should not hold granular health data.

### Writing — the interesting direction

**REQ-DATA-007.** Memento should offer to write the entry's inferred mood back to Health as an `HKStateOfMind` sample. Off by default, one-tap opt-in.

This makes Memento a first-class citizen of the user's own Health data rather than another silo. Their journal-derived mood shows up alongside everything else Health tracks, in an app they already trust, and it survives Memento being deleted. That's a genuinely pro-user design and no competitor does it.

### 🔴 The App Review question — DEC-006

**Health data MUST NOT be sent to PCC** without resolving this first.

App Review has historically been strict about HealthKit data leaving the device and about its use for anything resembling advertising or profiling. Sending health-derived context into a third-party model prompt — even Apple's own, even on PCC — is untested ground.

**Conservative default: exclude health data from all Z1 prompts entirely.** Health context may be used *on-device* to **select** which entries go into a reflection, and may be summarized in Z0 into a neutral phrase ("a week with poor sleep") before any Z1 call. Verify with Apple before doing even that.

The correlation feature does not require health data in the prompt. Computing "you wrote about feeling flat on six of eight nights following under six hours of sleep" is a **Z0 statistical operation** whose *result* — not whose inputs — can inform prose. Prefer that architecture regardless of what App Review permits, because it's better engineering.

---

## 4. WeatherKit

🟡 **LIKELY**

```swift
import WeatherKit

let weather = try await WeatherService.shared.weather(for: location)
// Store a short summary string on the entry
```

Captured at entry time, with permission, stored as a short string. Requires a WeatherKit entitlement (included with the developer program, with a request quota).

**Why it earns its place:** weather is the cheapest possible pattern ingredient and it produces the most striking observations. *"You've written about feeling flat on six of the last eight overcast Mondays"* is the kind of line that makes someone screenshot an app. It requires one framework and no server.

Note: WeatherKit calls are network calls to Apple. They contain a location, not journal content. Disclose in the privacy explainer; they do not violate the Z1 boundary but they are not Z0 either. Make the setting explicit and off by default.

---

## 5. Location

🟡 **LIKELY**

Coarse place name only, reverse-geocoded **on-device**:

```swift
import CoreLocation
// Request .reducedAccuracy — Memento does not need precise coordinates
```

Request **reduced accuracy**. A journal needs "at home," "at the office," "somewhere near the park" — not GPS coordinates. Requesting full accuracy for this is both unnecessary and a bad signal in the permission prompt.

Store the place name string, not the coordinates.

---

## 6. Universal rules for all ambient context

**REQ-CAP-012 and the honesty requirement:**

1. **Every source is optional, off until granted, and excludable per-entry and globally.**
2. **Correlation language only. Never causal.** "You often write about feeling low on days you slept under six hours" — never "poor sleep is making you unhappy." Memento is not a clinician and must never imply mechanism.
3. **Every charted correlation shows its n.** A pattern claimed over four entries is noise. REQ-SUR-001 requires the UI make sample size legible so the prose cannot imply significance the data doesn't support.
4. **Ambient context is a Z0 input by default.** Summarize before it goes anywhere near a Z1 prompt.
5. **Ask in context, late.** Do not front-load five permission prompts in onboarding. Ask for weather the first time a user opens the Patterns view. Ask for Health when they tap a mood chart.

---

## 7. Swift Charts — where this becomes visible

🟡 **LIKELY**

The Patterns surface is where these frameworks pay off visually: mood valence over time, topic frequency, capture cadence, and — where authorized — sleep, workouts, weather, and place overlays.

**Design rule:** the monthly reflection *reads the chart*, not the other way around. Compute the statistics on-device with real math (or a custom Spotlight pipeline stage — see `03-spotlight-retrieval.md` §9), then hand the model the computed result to narrate. Never ask the model to count things in prose and then chart its answer. That is how journaling apps end up confidently reporting patterns that do not exist.
