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

✅ **VERIFIED** (session 319)

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

Note it's used directly in a SwiftUI `body` — the model type is observable. 🟡 LIKELY that it conforms to `Observable`; confirm.

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

Surface area confirmed:

- `model.quotaUsage.status` → `.belowLimit(info)` and presumably other cases 🔴 (enumerate against SDK)
- `info.isApproachingLimit` → Bool
- `model.quotaUsage.isLimitReached` → Bool
- `model.quotaUsage.limitIncreaseSuggestion` → optional, with `.show()` to present system upgrade options

### Apple's explicit guidance

✅ VERIFIED: **"show persistent, actionable UI (such as a disabled button with an upgrade option) rather than an alert."**

This aligns exactly with Memento's degradation principle (P5: degrade visibly, never silently). Do not use alerts for quota. Use inline, persistent, honest state.

### Open question

🔴 **UNVERIFIED:** is the daily limit **per-app** or **per-user across all apps**? This materially changes `QuotaGovernor` design:

- **Per-app:** Memento can budget precisely — reserve capacity for Sunday's reflection, spend the rest on chat.
- **Per-user-across-apps:** Memento cannot know true remaining budget (another app may consume it), so the governor must be purely reactive and the reservation strategy becomes advisory rather than reliable.

The presence of `limitIncreaseSuggestion` pointing at iCloud+ implies **per-user**, since iCloud+ is an account-level subscription. Plan for per-user; verify.

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
- Degradation copy is a design deliverable, not a string constant. Draft: *"Written on your iPhone. Shorter than usual — your daily reflection allowance is used up until tomorrow."*

---

## 9. watchOS

✅ VERIFIED (session 319): PCC is available on watchOS 27.

This is more significant than it sounds. It means a Watch-captured entry could in principle be reflected on without the phone. Scoped to Memento 2.1 — but do not design the data layer in a way that forecloses it.

---

## 10. Testing

✅ VERIFIED: Xcode ships a **"Simulate Apple Foundation Models Availability"** debug option that lets you test both the unavailable state and the quota-exhausted state.

**Requirement:** every Z1 surface must have a UI test exercising all three states — available, approaching limit, limit reached — plus the unavailable case. These are not edge cases in a quota'd system; they are Tuesday.
