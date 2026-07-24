# Memento 2.0 — Agent Reference Library

**Purpose:** This library exists so that an implementation agent working on Memento does not have to guess at Apple framework behavior, and does not fall back on training data that predates WWDC26. Several of these APIs shipped in June 2026 and behave differently from anything in a model's pre-2026 knowledge.

**Read this file first. Then read only the files relevant to your task.**

---

## Confidence legend

Every claim in this library carries one of three markers. **Respect them.** The difference between a verified API signature and an inferred one is the difference between working code and a wasted afternoon.

| Marker | Meaning | How to treat it |
|---|---|---|
| ✅ **VERIFIED** | Taken directly from Apple's WWDC26 session code samples or official documentation. Signature is quoted as Apple presented it. | Trust it. Still compile-check against the SDK. |
| 🟡 **LIKELY** | Established pre-2026 API that has been stable for multiple releases, or a strong inference from verified material. | Trust the concept; confirm the exact signature. |
| 🔴 **UNVERIFIED** | Assumed, inferred, or remembered. May be wrong. May not exist. | **Do not write code against this without checking the SDK first.** Add it to the verification queue. |

Anything marked 🔴 that blocks work goes to `11-verification-queue.md`.

---

## Files

| File | Covers | Read when |
|---|---|---|
| `01-foundation-models.md` | `LanguageModelSession`, `@Generable`, `Tool`, Dynamic Profiles, `LanguageModel` protocol, context sizes, vision input | Any generation work |
| `02-private-cloud-compute.md` | `PrivateCloudComputeLanguageModel`, reasoning levels, `quotaUsage`, eligibility, fallback | Weekly/monthly/chat surfaces |
| `03-spotlight-retrieval.md` | Core Spotlight donation, `SpotlightSearchTool`, guidance profiles, custom pipeline stages, `ContactResolver` | Retrieval, search, the Ask surface |
| `04-evaluations.md` | `Evaluations` framework, `ModelSampleProtocol`, `TrajectoryExpectation`, metrics | Quality gates, the 30-day study |
| `05-data-swiftdata-cloudkit.md` | SwiftData, CloudKit mirroring, data protection, app lock | Persistence, sync, deletion |
| `06-speech-and-audio.md` | `SpeechAnalyzer`, `SpeechTranscriber`, `AVAudioSession`, `AVSpeechSynthesizer`, Personal Voice | Capture and voice output |
| `07-app-intents-and-surfaces.md` | App Intents, entity/intent schemas, Siri, widgets, Controls, Live Activities, background tasks | System integration |
| `08-context-frameworks.md` | Journaling Suggestions, HealthKit State of Mind, WeatherKit, CoreLocation | Ambient context, patterns |
| `09-ui-swift6-testing.md` | SwiftUI, Liquid Glass, Swift Charts, Core Haptics, accessibility, Swift 6 concurrency, Swift Testing | Any UI or concurrency work |
| `10-monetization-and-privacy.md` | StoreKit 2, RevenueCat, Small Business Program, privacy labels, entitlements | Paywall, App Store, compliance |
| `11-verification-queue.md` | Every 🔴 item, consolidated, with how to check | Before starting any phase |

---

## The five things that most often go wrong

An agent working on this codebase without context tends to make these specific mistakes. Read them before writing code.

**1. Assuming a 4K context window.**
The on-device model context is **4096 on iOS 26.0** and **8192 on iOS 27 on newer devices**. PCC is **32768**. ✅ VERIFIED. Code that hardcodes a token budget will be wrong on some devices. Read `SystemLanguageModel().contextSize` at runtime.

**2. Reaching for a vector database.**
Memento has no vector store, no embedding model, and no similarity search. Retrieval is `SpotlightSearchTool` over the Core Spotlight index. If a task seems to need embeddings, re-read `03-spotlight-retrieval.md` — the answer is almost certainly a guidance profile or a custom pipeline stage.

**3. Scattering `import FoundationModels`.**
Exactly one module may import it (architecture principle P3). Every other module talks to `IntelligenceService`. If you find yourself importing FoundationModels in a view, you are in the wrong layer.

**4. Treating PCC as "the cloud."**
PCC is inside the trust boundary. It requires no API key, costs the developer nothing, and stores nothing. But it **has a per-user daily quota** and **requires a network connection**, so every PCC call needs a designed on-device fallback. Silent degradation is a spec violation.

**5. Generating markdown in user-facing prose.**
Every reflection Memento produces is also spoken aloud by `AVSpeechSynthesizer`. Bullet points, headers, asterisks, and emoji all read terribly. Prompts forbid them and a linter enforces it. See `06-speech-and-audio.md` §Speakability.

---

## Architectural non-negotiables

These come from the architecture spec and are not open for an agent to relitigate:

- **No developer-operated server.** No API endpoint holding user content, ever.
- **No third-party AI.** Only Apple's models. The provider-swap seam exists for survivability, not convenience.
- **One third-party SDK** (RevenueCat), and it never receives content.
- **Device is the system of record.** SwiftData is authoritative; CloudKit replicates.
- **Trust zones are typed.** Every generation request declares Z0 (device) or Z1 (Apple/PCC). Z2 (third party) does not exist for content.
- **Citations are mandatory.** Any claim about the user's history traces to an `Entry.id`.

---

## Primary sources

The WWDC26 sessions this library is built from. When something here is ambiguous, go to the source.

- **Session 241** — What's new in the Foundation Models framework
  `https://developer.apple.com/videos/play/wwdc2026/241/`
- **Session 319** — Build with the new Apple Foundation Model on Private Cloud Compute
  `https://developer.apple.com/videos/play/wwdc2026/319/`
- **Session 246** — LLM search using Core Spotlight
  `https://developer.apple.com/videos/play/wwdc2026/246/`
- **Docs — Spotlight search tool**
  `https://developer.apple.com/documentation/CoreSpotlight/Spotlight-search-tool`
- **Docs — Making your indexed content available to Foundation Models**
  `https://developer.apple.com/documentation/CoreSpotlight/making-your-indexed-content-available-to-foundation-models`
- **Docs — Adding server-side intelligence with Private Cloud Compute**
  `https://developer.apple.com/documentation/FoundationModels/adding-server-side-intelligence-with-private-cloud-compute`
- **Docs — Expanding generation with tool calling**
  `https://developer.apple.com/documentation/FoundationModels/expanding-generation-with-tool-calling`
- **Docs — Composing dynamic sessions with instructions and profiles**
  `https://developer.apple.com/documentation/FoundationModels/composing-dynamic-sessions-with-instructions-and-profiles`
- **Docs — Analyzing images with multimodal prompting**
  `https://developer.apple.com/documentation/FoundationModels/analyzing-images-with-multimodal-prompting`

Related sessions named but not yet reviewed: "Deep dive into the Foundation Models framework," "Meet the Evaluations framework," "Build agentic app experiences with Foundation Models," "Debug and profile agentic app experiences with Instruments," "Supporting semantic search with Core Spotlight" (prior year, prerequisite for session 246).
