# UI, Swift 6, and Testing

**Role in Memento:** the design and craft layer, which is the stated competitive advantage — plus the language and test conventions that keep the intelligence layer safe.

---

## 1. Swift 6 — strict concurrency

**REQ-PLAT-002:** Swift 6 language mode, strict concurrency checking set to **complete**.

This is not optional rigor. Memento's intelligence layer coordinates async generation, background tasks, quota state, an audio engine, and a SwiftData store. Data races here produce corrupted journal entries, which is the worst possible defect in this product.

### Isolation model

| Component | Isolation |
|---|---|
| `IntelligenceService` | `actor` |
| `QuotaGovernor` | `actor` — mutable shared state by definition |
| `PromptRegistry` | `actor` or immutable value type |
| SwiftData `ModelContext` | `@MainActor` for UI contexts; background contexts explicitly |
| View models | `@MainActor` + `@Observable` |
| Audio engine wrapper | `actor`, with a `@MainActor` facade for UI state |

Every type crossing an isolation boundary must be `Sendable`. `GenerationRequest`, `GenerationOutcome`, and `TrustZone` are all declared `Sendable` in the architecture spec for this reason.

**Common trap:** SwiftData `@Model` classes are not `Sendable`. Pass identifiers (`PersistentIdentifier` or your own `UUID`) across actor boundaries and re-fetch, never the model object.

---

## 2. Observation

🟡 Use `@Observable` (the Observation framework), not `ObservableObject`/`@Published`. Note from `02-private-cloud-compute.md` that `PrivateCloudComputeLanguageModel` is used directly in a SwiftUI `body` reading `.isAvailable` and `.quotaUsage`, which implies it participates in Observation. ✅ VERIFIED usage pattern; 🔴 conformance unconfirmed.

---

## 3. SwiftUI and Liquid Glass

**REQ-SYS-012:** Liquid Glass, second-iteration design tokens, verified against the transparency-reduction accessibility control.

> **The full Liquid Glass API reference now lives in `12-liquid-glass.md`** —
> `glassEffect(_:in:)`, `Glass` variants, `GlassEffectContainer`, morphing, glass
> button styles, and the "never layer opaque fills under glass" rule. Read that
> file before touching any glass surface. The app adopts native `.glassEffect`
> directly (deployment target iOS 26.0; no wrapper, no availability gate) — see
> spec 024.

🔴 The second-iteration token names and any migration from the first iteration need SDK confirmation.

**Design guidance specific to Memento's position:** Slate's aesthetic — austere, monochrome, minimal — is the house style of a developer shipping four near-identical apps. It is a *category*, and it gets crowded. The unclaimed ground is **warmth**.

Every privacy-first journal in this space is cold on purpose and treats restraint as the entire personality. Memento's differentiation is a journal that remembers you, talks back, and speaks in your own voice — which is a fundamentally different emotional product, and one that needs a designer to get right because the failure mode is *creepy* rather than *boring*.

Two places to spend that specifically:

1. **Make the trust boundary legible.** A visible mode indicator between on-device-only and PCC-enhanced, present at the point of use, not buried in Settings. Users should be able to *see* where their words go. This is P4 in the architecture spec and it is a design deliverable.
2. **Treat audio as a design surface.** Almost nobody has done reflective audio well. Playback state, waveform, the moment a reflection begins speaking — these are unexplored.

### Foldables

**REQ-SYS-013:** hinge-state handling in SwiftUI. 🔴 Confirm the iOS 27 foldable layout APIs. Low effort, and the hardware ships this fall — being ready at launch is free visibility.

---

## 4. Swift Charts

🟡 **LIKELY** (stable framework)

Powers the Patterns surface: mood valence over time, topic frequency, capture cadence, correlations with sleep/weather/place.

**Hard rule (REQ-SUR-001): every charted correlation shows its n.** A pattern over four entries is noise, and the UI must make that legible rather than let adjacent prose imply significance. Design an explicit low-confidence state for charts — greyed, annotated, or suppressed entirely below a threshold.

Compute statistics on-device with real arithmetic, then hand the result to the model to narrate. See `08-context-frameworks.md` §7.

---

## 5. Core Haptics

🟡 **LIKELY**

**REQ-SYS-014.** Haptics are an underused emotional design surface in this category. Three moments worth designing:

- Capture start / stop — should feel like a physical act, not a UI tap
- Reflection ready — distinct, gentle, not an alert
- Personal Voice playback begin — 🔴 optional; test whether it enhances or intrudes

Respect the system haptics setting and never use haptics to compensate for slow feedback elsewhere.

---

## 6. Accessibility — non-negotiable

**REQ-A11Y-001 through 003:**

- Full **VoiceOver** support with meaningful labels on every control
- **Dynamic Type** through accessibility sizes — a journal is a reading app; this must actually work at the largest sizes, not merely not-crash
- **Reduce Motion** and **Increase Contrast**
- **Reduce Transparency** — required given Liquid Glass
- **Voice Control** compatibility: clear accessibility labels usable as spoken targets

**The dividend:** because every reflection is audio-renderable (`06-speech-and-audio.md`), Memento is substantially usable without reading. That is a real accessibility strength emerging from the TTS work at no extra cost. Make sure VoiceOver and reflection playback do not fight each other — test the interaction explicitly.

---

## 7. Testing — Swift Testing

✅ **VERIFIED** that the Evaluations framework integrates with Swift Testing (`@Test`, `#expect`) — see `04-evaluations.md`.

Use **Swift Testing**, not XCTest, for new tests.

### Required test coverage

| Area | What must be tested |
|---|---|
| **Retrieval** | recall@5 ≥ 0.85 on the gold set (`04-evaluations.md` Gate 1) |
| **Grounding** | citation accuracy, ungrounded claim rate |
| **Persona** | adversarial suite — no advice, no diagnosis, correct crisis routing |
| **Restraint** | `hasNothingToSay` fires on sparse periods |
| **Speakability** | every generated prose sample passes the linter — **fails the build** |
| **Degradation** | all four capability tiers; all three quota states |
| **Audio durability** | recording survives interruption, backgrounding, lock, route change |
| **Deletion** | all five stores empty after "delete everything" |
| **Provider swap** | `IntelligenceService` works with an injected alternative `LanguageModel` |
| **CloudKit schema** | container initializes; all mirroring constraints satisfied |

### Testing the untestable bits

- **Quota states:** Xcode's "Simulate Apple Foundation Models Availability" debug option ✅ VERIFIED
- **App Intents:** the App Intents Testing framework, which validates through real system pathways without UI automation ✅ VERIFIED
- **Generation latency:** the Xcode 27 Foundation Models instrument — do not build custom timing ✅ VERIFIED

### Fixture corpus

A single shared fixture corpus serves retrieval tests, evaluation gates, and prompt iteration:

- ≥ 250 synthetic entries
- ≥ 8 months of simulated history
- ≥ 40 gold questions with known-correct entry IDs
- Deliberate sparse periods (for `hasNothingToSay`)
- Deliberate emotionally heavy content (for guardrail refusal rate)
- Deliberate adversarial prompts (for persona adherence)

Build this in Phase 0, before deleting anything. It is the instrument that tells you whether the rebuild worked.
