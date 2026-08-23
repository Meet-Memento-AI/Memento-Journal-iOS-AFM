# Private Cloud Compute (PCC)

**Import:** `import FoundationModels`
**Availability:** iOS 27, iPadOS 27, macOS 27, **watchOS 27**, visionOS 27
**Role in Memento:** Zone Z1. Powers weekly reflection, monthly insight, and the Ask surface.

---

## 1. What it actually is

✅ **VERIFIED** (session 319)

A frontier-class Apple server model reachable from the Foundation Models framework with:

- **No account setup, no authentication, no API keys**
- **No token cost to the developer**
- **A daily per-user limit**, higher for iCloud+ subscribers
- **Eligibility: apps under 2M first-time downloads**, developer enrolled in the App Store Small Business Program
- Data is **never stored**, used only for the request, and **independently verified**

The last point is the one that matters for Memento's positioning. PCC is not "a cloud API with a good privacy policy." It is attested infrastructure with external verification. That is why it sits in Z1 rather than Z2.

**Apply for access at the Apple developer website.** ✅ VERIFIED that an application is required (session 319, "Next steps"). Lead time unknown — 🔴 file this in week 1.

---

## 2. The one-line switch

✅ **VERIFIED** (session 319; verified against iOS 27.0 SDK (27A5228h), 2026-07-25)

SDK declarations confirmed in the FoundationModels swiftinterface:

```swift
// iOS 27.0+, watchOS 27.0+, tvOS unavailable
final public class PrivateCloudComputeLanguageModel : Sendable
convenience public init()                    // no-argument init, exactly as documented
extension PrivateCloudComputeLanguageModel : LanguageModel

// iOS 27 adds generic session inits that accept any LanguageModel:
convenience init(model: some LanguageModel, tools: [any Tool] = [], instructions: Instructions? = nil)
convenience init(model: some LanguageModel, tools: [any Tool] = [], transcript: Transcript)
```

⚠️ **DIFFERS:** the code sample below shows `tools: [FindRelatedArticlesTool.self]`
(metatype). The SDK session inits take `tools: [any Tool]` — **instances only**. No
metatype-accepting registration exists in the public interface. Use `tools: [FindRelatedArticlesTool()]`.

```swift
// On-device
let session = LanguageModelSession()

// PCC — one line different
let session = LanguageModelSession(
    model: PrivateCloudComputeLanguageModel()
)
```

Structured output and tools work identically:

```swift
@Generable
struct ArticleSummary {
    let oneLineSummary: String
    let keyPoints: [String]
}

let session = LanguageModelSession(
    model: PrivateCloudComputeLanguageModel(),
    tools: [FindRelatedArticlesTool.self]
)

let response = try await session.respond(
    to: "Summarize this article: \(article)",
    generating: ArticleSummary.self
)
```

This is why Memento's routing table is genuinely cheap to implement: the call sites are identical, only the injected model differs.

---

## 3. On-device vs PCC — the actual tradeoff

✅ **VERIFIED** (session 319, chapter at 4:00)

| | On-device (`SystemLanguageModel`) | PCC (`PrivateCloudComputeLanguageModel`) |
|---|---|---|
| Network required | No — works offline | **Yes** |
| Request limits | None | **Daily per-user quota** |
| Context window | 4096 (iOS 26) / 8192 (iOS 27, newer devices) | **32768** |
| Reasoning | No | **Yes — `.light`, `.moderate`, `.deep`** |
| Latency | Lower | Higher |
| Privacy | Z0 | Z1 |
| Cost to developer | Zero | Zero |

Both offer privacy. The decision is context size, reasoning, and offline capability — not trust.

⚠️ Note (SDK sweep 2026-07-25): the numeric window sizes (8192 / 32768) are **not SDK constants** — they are runtime values. `PrivateCloudComputeLanguageModel.contextSize` is `get async throws` (it may need the network); read it at runtime, never hardcode 32768. See `01-foundation-models.md` §3.

---

## 4. Availability checking

✅ **VERIFIED** (session 319)

```swift
struct ReflectionView: View {
    private var model = PrivateCloudComputeLanguageModel()

    var body: some View {
        if model.isAvailable {
            // Show UI for making request
        } else {
            // Fall back
        }
    }
}
```

Note it's used directly in a SwiftUI `body` — the model type is observable. ✅ **VERIFIED** — it conforms to `Observable`; exact declaration from the swiftinterface (verified against iOS 27.0 SDK (27A5228h), 2026-07-25; resolves V19):

```swift
extension PrivateCloudComputeLanguageModel : nonisolated Observation.Observable {}
```

Also confirmed on the same type:

```swift
final public var isAvailable: Bool { get }
final public var availability: Availability { get }

@frozen public enum Availability : Equatable, Sendable {
    case available
    case unavailable(UnavailableReason)
}
public enum UnavailableReason : Equatable, Sendable {   // nested in Availability
    case deviceNotEligible
    case systemNotReady
}
```

The `UnavailableReason` cases give Memento a designed copy opportunity per reason ("this device can't" vs "Apple Intelligence still setting up"), not just a boolean fallback.

**Memento requirement:** availability must be checked before presenting any Z1 affordance. On non-Apple-Intelligence devices this is always false, which is what drives the Reduced capability tier.

---

## 5. Reasoning levels

✅ **VERIFIED** (session 319)

```swift
let response = try await session.respond(
    to: prompt,
    contextOptions: ContextOptions(reasoningLevel: .light)
)
// Levels: .light, .moderate, .deep
```

✅ Verified against iOS 27.0 SDK (27A5228h), 2026-07-25 — with one **DIFFERS**:

```swift
public struct ContextOptions : Sendable, Equatable {          // iOS 27.0+
    public var includeSchemaInPrompt: Bool?
    public var reasoningLevel: ContextOptions.ReasoningLevel?
    public init(includeSchemaInPrompt: Bool? = nil, reasoningLevel: ReasoningLevel? = nil)
}
extension ContextOptions {
    public enum ReasoningLevel : Sendable, Equatable {
        case light
        case moderate
        case deep
        case custom(String)
    }
}
```

⚠️ **DIFFERS:** there is a **fourth case, `.custom(String)`** ("a level that indicates a
level not supported by the other cases," per the SDK doc comment), beyond the WWDC-derived
`.light/.moderate/.deep`. Any exhaustive switch over `ReasoningLevel` must handle it; Memento's
routing table has no use for it — do not expose it in `ModelRouter`'s column type.

Reasoning makes the model **think before responding by generating extra transcript text**. Two consequences:

1. **Reasoning consumes tokens against the 32K context limit.** A `.deep` call over a large retrieved entry set can exhaust context before producing output. Budget accordingly.
2. **You can observe the transcript to show progress.** ✅ VERIFIED. For Memento's monthly insight — which may take a while — surfacing "thinking" progress is a legitimate design opportunity rather than a spinner.

**Memento routing recommendation (to be validated with Evaluations, not vibes):**

| Surface | Reasoning level | Why |
|---|---|---|
| Weekly reflection | `.moderate` | Synthesis across ~7–20 entries; doesn't need deep chains |
| Monthly insight | `.deep` | Cross-period pattern detection, the heaviest reasoning task |
| Ask (chat) | `.light` | Latency matters in conversation; retrieval does the heavy lifting |

Apple's explicit guidance: **"Choose models and reasoning levels based on data, not vibes; the updated on-device model may surprise you."** ✅ VERIFIED. Run this through the Evaluations framework (`04-evaluations.md`) before locking the table.

---

## 6. Quota handling — the API exists

✅ **VERIFIED** (session 319). This resolves what was previously a blocking unknown in the architecture spec.

```swift
struct ReflectionView: View {
    private var model = PrivateCloudComputeLanguageModel()

    var body: some View {
        if case .belowLimit(let info) = model.quotaUsage.status {
            if info.isApproachingLimit {
                Text("Nearing usage limit.")
                    .foregroundStyle(Color.orange)
            }
        }
        if model.quotaUsage.isLimitReached {
            Text("Usage limit exceeded.")
                .foregroundStyle(Color.red)
        }
        if let suggestion = model.quotaUsage.limitIncreaseSuggestion {
            Button("Show options") {
                suggestion.show()
            }
        }
    }
}
```

Surface area — ✅ **fully enumerated against iOS 27.0 SDK (27A5228h), 2026-07-25** (resolves V13):

```swift
extension PrivateCloudComputeLanguageModel {
    public struct QuotaUsage : Sendable {
        public var status: QuotaUsage.Status
        public var limitIncreaseSuggestion: QuotaUsage.LimitIncreaseSuggestion?
        public var resetDate: Date?                      // ← new vs WWDC material
    }
}
extension PrivateCloudComputeLanguageModel.QuotaUsage {
    public var isLimitReached: Bool { get }              // computed convenience
    public enum Status : Sendable {                      // NOT @frozen
        case belowLimit(Status.BelowLimit)
        case limitReached(Status.LimitReached)
    }
    public struct LimitIncreaseSuggestion : Sendable {}  // opaque
}
extension ...QuotaUsage.Status {
    public struct BelowLimit : Sendable { public var isApproachingLimit: Bool }
    public struct LimitReached : Sendable {}             // no payload fields
}
extension ...QuotaUsage.LimitIncreaseSuggestion {
    public func show()
}
```

- **The full `status` case list is exactly two:** `.belowLimit(BelowLimit)` and `.limitReached(LimitReached)`. No third case.
- `Status` is **not `@frozen`** — spec 017 R3's requirement of a safe `@unknown default` arm in `QuotaGovernor` stands; the compiler will demand it in library-evolution mode.
- **New vs WWDC expectations:** `quotaUsage.resetDate: Date?` — the date the limit resets. `QuotaGovernor` should use it to schedule retry of a deferred Sunday reflection instead of polling.
- Errors surface as `PrivateCloudComputeLanguageModel.Error` (`LocalizedError`): `.networkFailure(NetworkFailure)`, `.quotaLimitReached(QuotaLimitReached)`, `.serviceUnavailable(ServiceUnavailable)`. `QuotaLimitReached` carries `limitIncreaseSuggestion: LimitIncreaseSuggestion?` and `resetDate: Date?` — so the reset date is available at the failure site too, not only via polling `quotaUsage`.

### Apple's explicit guidance

✅ VERIFIED: **"show persistent, actionable UI (such as a disabled button with an upgrade option) rather than an alert."**

This aligns exactly with Memento's degradation principle (P5: degrade visibly, never silently). Do not use alerts for quota. Use inline, persistent, honest state.

### Open question

🟡 **PARTIALLY RESOLVED** (V4 — SDK evidence gathered 2026-07-25, iOS 27.0 SDK 27A5228h): is the daily limit **per-app** or **per-user across all apps**?

The SDK's doc comment for `QuotaUsage` (from the module's `.swiftdoc`; the swiftinterface itself carries no doc comments) reads, verbatim:

> "The usage quota state for a Private Cloud Compute language model. A quota describes the model's **per-user request budget** and where the caller currently sits relative to it. Quotas are orthogonal to a model's availability — a model can be available even after its usage limit has been reached."

- **"Per-user request budget"** is Apple's own wording — this confirms the per-user framing. It does **not** explicitly say "shared across all apps"; nothing anywhere in the interface or doc comments mentions per-app scoping, and no app-scoped quota API exists on the surface.
- The design consequence stands as planned: `QuotaGovernor` is **reactive** — observe `quotaUsage`, treat reservation as advisory (spec 017 R3's posture is unchanged and now SDK-supported).
- **Per-app:** would have let Memento budget precisely — no supporting evidence found; do not design for it.
- Also note the orthogonality sentence: `isAvailable == true` does **not** imply budget remains. Check `quotaUsage`, not availability, before a Z1 attempt.

Definitive cross-app confirmation would require empirical testing with two apps on one device/account — out of scope for an SDK-surface sweep.

---

## 7. Memento's quota strategy

Given a shared per-user daily budget, Memento's priority order is fixed:

> **weekly reflection > monthly insight > chat**

A user must never lose their Sunday reflection because they had a long conversation on Saturday. Implement as:

1. `QuotaGovernor` actor observes `quotaUsage` and tracks local consumption by intent.
2. Chat has a **soft internal rate limit below the system limit** so Memento degrades on its own terms with designed copy, rather than hitting an opaque system state.
3. When `isApproachingLimit` fires, chat degrades to Z0 first, preserving remaining budget for scheduled reflections.
4. Scheduled reflections run via background task, preferentially at times of low contention (see `07-app-intents-and-surfaces.md` on `BGProcessingTask`).

---

## 8. Degradation contract

Non-negotiable, from the architecture spec:

- Degradation Z1 → Z0 is **attempted automatically**, **completed successfully**, and **disclosed** — both persisted (`Reflection.zone`, `Turn.wasDegraded`) and rendered in the UI.
- Degraded output uses a **different prompt** tuned for the smaller model, never the PCC prompt with a smaller model behind it. Reusing the heavy prompt on the light model produces confident, ungrounded, badly structured output — the worst failure mode available.
- Degradation copy is a design deliverable, not a string constant. Draft: *"Written on this device. Shorter than usual — your daily reflection allowance is used up until tomorrow."*

---

## 9. watchOS

✅ VERIFIED (session 319): PCC is available on watchOS 27.

This is more significant than it sounds. It means a Watch-captured entry could in principle be reflected on without the phone. Scoped to Memento 2.1 — but do not design the data layer in a way that forecloses it.

---

## 10. Testing

✅ VERIFIED: Xcode ships a **"Simulate Apple Foundation Models Availability"** debug option that lets you test both the unavailable state and the quota-exhausted state.

**Requirement:** every Z1 surface must have a UI test exercising all three states — available, approaching limit, limit reached — plus the unavailable case. These are not edge cases in a quota'd system; they are Tuesday.
