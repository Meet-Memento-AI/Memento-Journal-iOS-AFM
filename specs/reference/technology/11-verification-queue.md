# Verification Queue

Every 🔴 UNVERIFIED item in this library, consolidated. **Work this list before starting the phase that depends on it.**

This library was assembled from WWDC26 session material, Apple documentation, and secondary sources in July 2026. API surfaces in developer beta change. Anything below is a claim that has *not* been confirmed against a compiling SDK.

---

## P0 — Blocking the architecture

### V1. Can Spotlight donation be hidden from system-wide search?

**Blocks:** the entire retrieval architecture, and therefore Phases 1–3.
**Reference:** `03-spotlight-retrieval.md` §8, architecture spec DEC-002.

If journal entries donated to Core Spotlight surface in system-wide search, someone can pick up an unlocked iPhone, type a word, and read a private journal line. Category-ending.

**Test sequence:**
1. Enumerate `SpotlightSearchTool.Configuration.sources` cases in the SDK.
2. Donate to `CSSearchableIndex(name: "memento-entries")` rather than `.default()`. Confirm items do **not** appear in system Spotlight UI on a real device.
3. Confirm `SpotlightSearchTool` can still retrieve from that named index.
4. Check whether the index respects Data Protection / device lock.
5. Check `CSSearchableItemAttributeSet` for any exclude-from-system-UI attribute.

**If negative:** activate Fallback A (opt-in indexing, default off) or Fallback B (hand-rolled SwiftData retrieval tool). Both are specified in `03-spotlight-retrieval.md` §8.

**Written verdict 2026-08-19 (DEC-002): negative / Plan B.** SDK enumeration found no named-index source on `SpotlightSearchTool`. Default-off donation + `EntryRetriever`. Device Gate α still fills the system-UI and recall@5 rows; it does not reopen the hiding question.

---

## P1 — Calendar dependencies (file in week 1)

### V2. PCC access application — 🟡 process confirmed 2026-07-23, still open to file
**Reference:** `10-monetization-and-privacy.md` §1, §7; spec 013 R5.
Two-step chain, not one: (a) Small Business Program self-serve enrollment
(`developer.apple.com/app-store/small-business-program/enroll/`, eligibility
≤$1M prior-year proceeds or new developer), then (b) a **separate, genuinely
gated** PCC request at `developer.apple.com/contact/request/private-cloud-compute/`.
**Lead time still unknown** — Apple's docs don't state one — this remains the
longest-lead item in the plan. Still open: actually filing both (requires the
account holder's Apple Developer login, not agent-executable).

### V3. Journaling Suggestions entitlement — 🟡 corrected 2026-07-23, likely not a P1 item at all
**Reference:** `08-context-frameworks.md` §2; spec 013 R5.
Research (Apple docs + developer-forum search) did **not** support the
"requires a request to Apple with review lead time" framing this item was
filed under. `com.apple.developer.journal.allow` appears to be a standard
Xcode-addable capability since Xcode 15.1 beta/iOS 17.2 — no discoverable
request-form URL, unlike V2's PCC endpoint. Not ✅ because Apple's entitlement
reference page didn't yield fetchable body content through available
tooling; confirm with one click (Xcode → Signing & Capabilities → search
"Journal") before fully closing. If confirmed, this drops out of P1 entirely
— it was never actually a calendar dependency.

---

## P1 — Changes design if wrong

### V4. Is the PCC daily limit per-app or per-user across apps? — 🟡 per-user confirmed in SDK doc comment 2026-07-25; cross-app sharing still inferential
**Reference:** `02-private-cloud-compute.md` §6; spec 017 R3.
Verified against iOS 27.0 SDK (27A5228h): the `QuotaUsage` doc comment (module `.swiftdoc`) reads verbatim: *"A quota describes the model's **per-user request budget** and where the caller currently sits relative to it. Quotas are orthogonal to a model's availability — a model can be available even after its usage limit has been reached."* No per-app scoping appears anywhere in the interface or doc comments, and no app-scoped quota API exists.
- **Per-user is Apple's own wording** — `QuotaGovernor` stays reactive-first (spec 017 R3 posture unchanged, now SDK-supported). Reservation remains advisory.
- Cross-app sharing is not *explicitly* stated; definitive confirmation needs an empirical two-app test on one device — not resolvable from the SDK surface. Do not block on it; no design decision hinges on the residual.
- Bonus from the sweep: `quotaUsage.resetDate: Date?` exists (also on the `.quotaLimitReached` error payload) — the governor can schedule retries instead of polling.

### V5. `NSFileProtectionComplete` vs `BGProcessingTask` — 🟡 header-level verified 2026-07-25, device test still open
**Reference:** `05-data-swiftdata-cloudkit.md` §4.
Verified against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4): all five protection
constants present and unchanged (`None`, `Complete`, `CompleteUnlessOpen`,
`CompleteUntilFirstUserAuthentication`, plus `CompleteWhenUserInactive`, ios(17.0)).
The `NSFileProtectionComplete` header doc confirms the risk verbatim: "cannot be
read from or written to while the device is locked or booting." Neither the
SwiftData nor CloudKit module interface mentions protection classes (searched
both — zero hits), so no framework carve-out exists. **Still open (behavioral):**
whether `BGProcessingTask` runs while locked in practice and therefore whether
`.complete` starves weekly generation — an on-device test, not a header question.

### V6. Personal Voice — App Review posture for non-accessibility use
**Reference:** `06-speech-and-audio.md` B3.
Personal Voice was introduced as an accessibility feature. Confirm that use in a journaling app is permitted **before building the flow**. This is a real risk, not a formality — it is the differentiating feature.

### V7. HealthKit data in third-party model prompts
**Reference:** `08-context-frameworks.md` §3, architecture spec DEC-006.
Conservative default is to exclude health data from all Z1 prompts. Verify with Apple whether even a Z0-summarized neutral phrase is acceptable. Note the correlation feature does not require it.

### V8. RevenueCat SDK impact on "Data Not Collected" label
**Reference:** `10-monetization-and-privacy.md` §5.
If it triggers a collection disclosure, evaluate StoreKit 2 direct. The label is worth more than the dashboard.

---

## P2 — API surface confirmation

### V9. `SpotlightSearchTool.Configuration.sources` — full case list
✅ **RESOLVED** (iOS 27.0 SDK, 27A5228h, 2026-07-25). `SearchSource` is a struct with exactly **two families**, each in bare and configured form: `.coreSpotlight` / `.coreSpotlight(CoreSpotlightSource)` and `.files` / `.files(FileSource)`. Default is `Configuration(sources: [.coreSpotlight])`. `CoreSpotlightSource(searchableIndexDelegate:fetchAttributes:)` also has `maximumResultCount: Int?`; `FileSource` adds `scopes: [URL]`. **For V1/DEC-002: there is no named/private-index source — `CoreSpotlightSource` has no index-name, `CSSearchableIndex`, or protection-class parameter.** Full declarations quoted in `03-spotlight-retrieval.md` §2. Note: all of this lives in the `_CoreSpotlight_FoundationModels` cross-import overlay (auto-loaded by importing both frameworks).

### V10. Tool registration form
✅ **RESOLVED** (iOS 27.0 SDK, 27A5228h, 2026-07-25). **Instance form is the only form.** Every `LanguageModelSession` initializer takes `tools: [any Tool] = []` — e.g. `convenience init(model: SystemLanguageModel = .default, tools: [any Tool] = [], instructions: Instructions? = nil)`. No metatype (`[MyTool.self]`) overload exists anywhere in the FoundationModels interface.
**Reference:** `01-foundation-models.md` §5; signatures quoted in `03-spotlight-retrieval.md` §3.

### V11. `GenerationOptions.ToolCallingMode`
✅ **RESOLVED — it exists** (iOS 27.0 SDK, 27A5228h, 2026-07-25). `GenerationOptions.toolCallingMode: ToolCallingMode?` is `@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)`. `ToolCallingMode` is a struct with `kind: Kind` (`enum Kind { case allowed, required, disallowed }`) and statics `.allowed` / `.required` / `.disallowed`, set via `GenerationOptions(samplingMode:temperature:maximumResponseTokens:toolCallingMode:)`. For the Ask surface, **`.required`** is the "always search, never answer from world knowledge" setting. A `toolCallingMode(_:)` builder also exists on `LanguageModelSession.DynamicProfile`.
**Reference:** `01-foundation-models.md` §5; quoted in `03-spotlight-retrieval.md` §3.

### V12. `SpotlightSearchTool` registered tool name
🟡 **OPEN — default string not recoverable from the SDK** (checked 2026-07-25). The swiftinterface declares `public var name: String` as a **settable stored property** with no visible default; the default is assigned in the runtime dylib, which is not on disk (SDK framework is a `.tbd` stub; only the iOS 26.0 simulator runtime is installed locally). The `.swiftdoc` contains no default-name string either. Two paths: (a) print `SpotlightSearchTool().name` on the first iOS 27 runtime/device available; (b) **moot the question** — since `name` is settable, pin it explicitly (e.g. `tool.name = "searchSpotlight"`) so trajectory expectations depend on a string Memento controls, not on Apple's default.
**Reference:** `04-evaluations.md` §3.

### V13. `quotaUsage.status` — full case list — ✅ RESOLVED, verified against iOS 27.0 SDK (27A5228h), 2026-07-25
**Reference:** `02-private-cloud-compute.md` §6 (updated with full declarations); spec 017 R3.
Exactly **two** cases: `case belowLimit(Status.BelowLimit)` (payload: `isApproachingLimit: Bool`) and `case limitReached(Status.LimitReached)` (empty payload). `QuotaUsage` = `{ status, limitIncreaseSuggestion: LimitIncreaseSuggestion?, resetDate: Date? }` plus computed `isLimitReached: Bool`; `LimitIncreaseSuggestion.show()` confirmed. `Status` is **not `@frozen`** — 017 R3's mandatory `@unknown default` arm stands.

### V14. Evaluations — Sample Generation APIs
Confirmed to exist; signature unknown. Would make a 200-query gold set feasible instead of hand-authoring 40.
**Reference:** `04-evaluations.md` §4.

### V15. `SpeechAnalyzer` / `SpeechTranscriber` exact initializers and result shape — ✅ RESOLVED, verified against iOS 27.0 SDK (27A5228h), 2026-07-25 (Speech.framework swiftinterface)
**Reference:** `06-speech-and-audio.md` A1.
`final public actor SpeechAnalyzer`, inits: `init(modules: [any SpeechModule], options: SpeechAnalyzer.Options? = nil)` and `init(inputSequence:modules:options:analysisContext:volatileRangeChangedHandler:)` (input: `AsyncSequence<AnalyzerInput>`). Key methods: `start(inputSequence:)`, `analyzeSequence(_:) -> CMTime?`, `finalize(through:)`, `finalizeAndFinishThroughEndOfInput()`, `prepareToAnalyze(in:withProgressReadyHandler:)`.
`final public class SpeechTranscriber : SpeechModule, LocaleDependentSpeechModule`, inits: `init(locale:preset:)` and `init(locale:transcriptionOptions:reportingOptions:attributeOptions:)`. Presets: `.transcription`, `.transcriptionWithAlternatives`, `.timeIndexedTranscriptionWithAlternatives`, `.progressiveTranscription`, `.timeIndexedProgressiveTranscription`. Results: `transcriber.results` is an `AsyncSequence<SpeechTranscriber.Result, any Error>`; `Result = { range: CMTimeRange, resultsFinalizationTime: CMTime, text: AttributedString, alternatives: [AttributedString] }`. Reporting options include `.volatileResults`, `.fastResults`; attribute options `.audioTimeRange`, `.transcriptionConfidence`.

### V16. `AssetInventory` API for locale model download and progress — ✅ RESOLVED, verified against iOS 27.0 SDK (27A5228h), 2026-07-25 (Speech.framework swiftinterface)
**Reference:** `06-speech-and-audio.md` A2.
`final public class AssetInventory` (all static): `status(forModules: [any SpeechModule]) async -> Status` with `Status : Comparable = { .unsupported, .downloading, .supported, .installed }`; `assetInstallationRequest(supporting: [any SpeechModule]) async throws -> AssetInstallationRequest?` where `AssetInstallationRequest : ProgressReporting` exposes `progress: Foundation.Progress` and `downloadAndInstall() async throws`. Locale reservation: `maximumReservedLocales: Int`, `reservedLocales: [Locale] { get async }`, `reserve(locale:) async throws -> Bool`, `release(reservedLocale:) async -> Bool`. Per SDK doc comment, models also download automatically "based on factors like network status, battery level, and system load."

### V17. AirPods high-quality recording API and hardware minimum — 🟡 API ✅ confirmed 2026-07-25, hardware minimum still open
**Reference:** `06-speech-and-audio.md` A5 (updated), A4 DIFFERS note.
Verified against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4):
`AVAudioSessionCategoryOptionBluetoothHighQualityRecording` (ios(26.0), `1 << 19`,
Swift `.bluetoothHighQualityRecording`); per-route query via
`AVAudioSessionPortExtensionBluetoothMicrophone.highQualityRecording` →
`AVAudioSessionCapability` (`isSupported`/`isEnabled`, iOS 26+). Two catches from
the header: it is "currently compatible only with mode `AVAudioSessionModeDefault`"
— i.e. **incompatible with A4's `.spokenAudio` mode** — and `.allowBluetooth` is
deprecated → `.allowBluetoothHFP`. **Still open:** hardware minimum — the header
says only "certain AirPods models"; determine empirically via `isSupported`.
(Personal Voice surface also swept 2026-07-25: `requestPersonalVoiceAuthorization`,
`personalVoiceAuthorizationStatus`, `voiceTraits.isPersonalVoice` all unchanged
iOS 17 declarations in the iOS 27 SDK — see `06` B3. App Review posture remains V6.)

### V18. Any iOS 27 speech synthesis API beyond `AVSpeechSynthesizer` — ✅ RESOLVED 2026-07-25: none shipped
Verified against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4). `AVSpeechSynthesis.h`
contains zero ios(26)/ios(27) additions; every `AVSpeechUtterance` init takes complete
input (`String` / `NSAttributedString` / SSML, iOS 16) — no streaming-text input
anywhere. SDK-wide header sweep for speech synthesis hit only `AVFAudio`'s
`AVSpeechSynthesis.h` + `AVSpeechSynthesisProvider.h` (iOS 16 custom-voice
extension host, request-based), an `AVFoundation` re-export shim, and incidental
mentions in Accessibility/AudioToolbox. The `Speech` framework has no synthesis
module (its modules: `SpeechTranscriber`, `DictationTranscriber`, `SpeechDetector`).
**The B1 complete-text constraint and the chat/reflection split stand.**

### V19. `PrivateCloudComputeLanguageModel` — `Observable` conformance — ✅ RESOLVED, verified against iOS 27.0 SDK (27A5228h), 2026-07-25
**Reference:** `09-ui-swift6-testing.md` §2; `02-private-cloud-compute.md` §4 (updated).
Exact declaration: `extension FoundationModels.PrivateCloudComputeLanguageModel : nonisolated Observation.Observable {}`. (`SystemLanguageModel` conforms too.) Also confirmed: `isAvailable: Bool`, and `availability: Availability` (`@frozen`: `.available` / `.unavailable(reason)` with `UnavailableReason = { .deviceNotEligible, .systemNotReady }`).

### V20. App Intents per-intent privacy manifest declarations
Reported for iOS 27. For a journal, every intent should be declared on-device if the mechanism allows.
**Reference:** `07-app-intents-and-surfaces.md` §1.

### V21. App Intents domain schemas — is there a journaling domain?
If not, use the generic entity path.
**Reference:** `07-app-intents-and-surfaces.md` §1.

### V22. View Annotations API
iOS 27 addition mapping views to entities for conversational reference ("summarize this entry"). Investigate after core surfaces ship.

### V23. Liquid Glass second-iteration token names and migration path
**Reference:** `09-ui-swift6-testing.md` §3.

### V24. iOS 27 foldable layout APIs — hinge-state handling in SwiftUI
**Reference:** `09-ui-swift6-testing.md` §3.

### V25. SwiftData `@Attribute(.allowsCloudEncryption)` — 🟡 API ✅ confirmed 2026-07-25, mirroring behavior still open
**Reference:** `05-data-swiftdata-cloudkit.md` §2 (updated).
Verified against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), `SwiftData.swiftmodule`:
`public static var allowsCloudEncryption: Schema.Attribute.Option { get }`
(@available macOS 14, iOS 17, …), accepted by the `@Attribute(_ options:
Schema.Attribute.Option...)` macro — the spelling compiles. No container/
configuration-level encryption knob exists; the attribute option is the whole
surface. CloudKit backing (`CKRecord.encryptedValues`, iOS 15+) documents the
limits: encryption cannot be added to already-deployed schema fields, and
encrypted fields cannot be indexed/queried/sorted. **Still open (behavioral):**
confirm on-device that the option round-trips through CloudKit mirroring for the
transcript field — the interface proves the spelling, not the mirroring behavior.

### V26. Spotlight index-readiness API
✅ **RESOLVED — NEGATIVE** (iOS 27.0 SDK, 27A5228h, 2026-07-25). **No readiness/catch-up API exists** in CoreSpotlight's public surface (full swiftinterface + all headers swept). Closest-but-insufficient: `isIndexingAvailable` (capability only), `CSIndexErrorCode.indexUnavailableError`, throttle delegate callbacks, `CSUserQuery.prepare()`. Per spec 016 R9, the degraded-retrieval state must therefore be **heuristic-triggered** (post-update window + anomalously empty results) and labeled as such.
**Reference:** `03-spotlight-retrieval.md` §12 (full negative finding recorded there).

### V27. Audio codec availability and target file sizes
**Reference:** `05-data-swiftdata-cloudkit.md` §6.

### V28. AFM 3 Core Advanced — on-device latency on minimum supported hardware — 🟡 context-size API surface resolved 2026-07-25; latency measurement still open
The p50 < 2s target for entry reflection depends on this. Measure with the Xcode 27 Foundation Models instrument on the oldest Apple Intelligence device, not on a current phone. **Not resolvable from the SDK surface** — remains open as a device task.
SDK findings (iOS 27.0 SDK, 27A5228h), see `01-foundation-models.md` §3: `SystemLanguageModel.contextSize: Int` is synchronous, back-deployed, and returns `4096` pre-iOS 27 (the only literal in the interface); `PrivateCloudComputeLanguageModel.contextSize` is `get async throws` — **8192 and 32768 exist nowhere as SDK constants**; both are runtime values, so context budgets must be read at runtime and the PCC read must handle a throw.

---

## P1 — Neural voice (specs 030–036, added 2026-08-18)

All three are device or policy questions. **None resolves from the SDK** — the
framework surface for all of them was swept against iOS 27.0 (27A5228h) on
2026-08-18 and recorded in `13-neural-tts-coreml.md`.

### V29. Is the Supertonic `VectorEstimator` graph ANE-resident with dynamic latent length?
🟡 **Owning spec: 031. Shapes RESOLVED 2026-08-18; placement still open.**

**Verified by compiling the bundle** (`xcrun coremlcompiler`, all four graphs
compile clean) and reading each `model.mil`: `TextEncoder` and
`DurationPredictor` are **fully fixed** at 128 text tokens; `VectorEstimator`
(`[1,144,?]`, RangeDims **17…512**) and `Vocoder` (`[1,144,?]`, RangeDims
**4…512**) are dynamic on **one bounded axis only**. That is a much better
starting position than open-ended dynamic shapes, and it makes `DEC-008`'s
contingency *enumerated shapes* rather than triplicated graphs — the ~730 MB
worst case is withdrawn.

**Also discovered, and it belongs to spec 032:** text is hard-capped at **128
tokens per synthesis call**. Longer text must be split by the app.

**What remains 🔴:** actual compute-unit placement, which no amount of file
reading answers. Variable-length inputs silently falling off the Neural
Engine onto GPU/CPU is a known Core ML failure mode, and `MLComputeUnitsAll` is a
request rather than a guarantee (`13-neural-tts-coreml.md` §2 — enum ✅ VERIFIED).
**How to check:** load the FP16 bundle in a scratch project and run Xcode's Core ML
performance report **on a physical device**; it prints per-layer compute-unit
placement. **Corrected 2026-08-18:** the graph is **`VectorEstimator`** (the flow-matching
estimator, 243 MB of a 331 MB bundle, run iteratively), not "text_to_latent" —
that name does not exist in the export. Check `TextEncoder` as well, but
`VectorEstimator` decides latency. **If negative:** activate `DEC-008` — export
fixed-shape variants, pad inputs, chunk above the largest bucket, and switch
`MLOptimizationHints.reshapeFrequency` to `.infrequent`. Weigh the cost
honestly: 3× a 243 MB graph is ~730 MB on a bundle already over spec 030 R7's
threshold, so bucketing may be infeasible rather than merely expensive. **Blocks:** all of spec 031's engine code (CONSTITUTION rule 10).
**Reference:** `13-neural-tts-coreml.md` §2–§3.

**Partial answer, measured on device 2026-08-18** (iPhone 16 Pro, iOS 26,
Xcode 26.0.1). The dynamic axis is **not** merely a theoretical placement risk —
it is a hard incompatibility with **at least one** non-CPU backend, reproducibly:
under `MLComputeUnits.all`, `Vocoder` is dispatched to the **GPU via MPSGraph**,
which requires static shapes and fails outright (`invalid axis: -1258641855`,
`'shape for TensorData is not static'`). So the "variable-length inputs silently
fall off the ANE" concern above understates it for the GPU path, where the
failure is loud rather than silent.

Resolution shipped: `SupertonicCompute.cpuAndNeuralEngine` — **exclude the GPU,
keep the ANE**. With that, the engine runs end-to-end on device at **RTF 0.254**
(1.162 s wall for 4.568 s of 44.1 kHz audio, warm), all four voices render and
differ, and the log is clean.

**Still 🔴, and this is the part the measurement above does not answer:** whether
`VectorEstimator` is actually *ANE-resident* or is silently running on CPU inside
`.cpuAndNeuralEngine`. RTF 0.254 is comfortable but does not discriminate between
the two — an 8-bit-palettized graph on a fast CPU could plausibly produce it. The
Core ML performance report on device remains the only thing that closes V29.
Note the correction it must resolve: `DEC-008`'s enumerated-shapes contingency was
scoped to the *ANE* rejecting the dynamic axis, and the ANE is not what failed
here, so **`DEC-008` is not activated by this finding**.

### V30. Do all four candidate voices survive the voice-processing (AEC) path?
🔴 **Owning spec: 033.** `setVoiceProcessingEnabled:error:` is ✅ VERIFIED
(`AVAudioIONode.h`, ios 13.0) — the API is not in question. The **timbre cost**
is: voice-processing I/O is tuned for telephony intelligibility and audibly thins
and nasalizes output. **How to check:** render three real journal-reflection
passages in each candidate voice through an `AVAudioSession` `.playAndRecord`
graph with voice processing enabled, on a physical device, and listen. **If any
voice degrades:** swap the roster now and update spec 033's catalog — `DEC-009`.
A voice users bond with cannot be swapped cheaply after release, which is why
this is auditioned through the *degraded* path rather than the hi-fi one.
**Reference:** `13-neural-tts-coreml.md` §5.

### V31. Background Assets delivery — ⛔ WITHDRAWN 2026-08-18

**Withdrawn, not resolved.** `DEC-012` bundles the model in the app binary, so
every question this item existed to answer — App Review posture for a self-hosted
model pack, TLS/availability/CDN requirements, hosting ownership — is moot.
Nothing is hosted. The size half was answered anyway: 148 MB vendored, ~156 MB
app, under the 200 MB cellular-prompt threshold (spec `030` R7).

The API findings below remain accurate and are retained for provenance; they are
not a description of how the app ships.

<details><summary>Original entry</summary>

### V31 (original). Background Assets delivery — hosting model, App Review posture, size
🟡 **Owning spec: 030. Hosting half RESOLVED 2026-08-18; size measurement still open.**

**Finding that changes the design: Apple will host the assets for us.** The spec
assumed self-hosting because the SDK sweep found the self-hosted manifest API
first. App Store Connect documentation (fetched 2026-08-18) confirms
**Apple-hosted asset packs** as a first-class option for apps targeting iOS 26+
— which this app does (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`):

| Limit | Value |
|---|---|
| Asset pack total | **200 GB**, included in the Developer Program membership |
| Maximum asset packs per app | **200** |
| Scope | Shared across all platforms the app offers |

A ~250 MB model bundle is **0.125%** of that quota, so size is not a constraint
on the hosting decision. Apple-hosted packs are uploaded from Xcode's packaging
tool, versioned in App Store Connect, testable through TestFlight, and submitted
through App Review alongside the build.

**Why this is likely the better answer than self-hosting:** it removes the CDN,
TLS, and availability workstream entirely; availability becomes Apple's problem
rather than a single-developer operational risk; and it keeps asset delivery
inside the Apple trust boundary rather than introducing a Memento-operated
endpoint — which the product otherwise does not have at all
(`REQ-PRIV-001`, "no developer-operated server"). It does not weaken
`REQ-TTS-001`: delivery happens outside synthesis, model-load, and
voice-selection time either way.

**Consequence for spec 030 R2, which currently mandates self-hosting:** the
client API differs — Apple-hosted uses managed asset packs rather than
`BAAssetPackManifest.init(contentsOf:appGroupID:)` over a manifest we serve.
This is a **product/architecture decision for the owner**, recorded here rather
than taken unilaterally. Note that `REQ-TTS-002`'s compiled-in SHA-256 manifest
remains implementable and desirable under either model.

**Still open:** measured total bundle size (spec 030 R7's 250 MB escalation
threshold), and whether App Review treats a model-weight asset pack differently
from a content asset pack. Neither blocks the hosting decision.

---

<details><summary>Original entry, retained for provenance</summary>

🔴 **Owning spec: 030.** The **API half is ✅ RESOLVED** (2026-08-18): developer-
hosted "unmanaged" asset packs are supported — `BAAssetPackManifest.init(contentsOf:appGroupID:)`
(ios 26) over a developer-served JSON manifest, `BAAssetPackManager.ensureLocalAvailabilityOfAssetPack:`,
per-pack integer `version` plus `checkForUpdatesWithCompletionHandler:`, and
`URLForPath:` to hand Core ML a file URL (off the main thread — the header
requires it). **Still open (policy/infrastructure):** whether App Review treats a
self-hosted model-asset pack of this size differently from self-hosted content
assets; the measured total FP16 bundle size (spec 030 escalates above 250 MB);
and the TLS/availability/CDN requirements for Memento-controlled hosting.
**Reference:** `13-neural-tts-coreml.md` §6.

</details>

---

## How to work this list

1. **Download Xcode 27 beta.** Most of P2 resolves in an afternoon of autocomplete and header reading.
2. **Do V1 on a real device**, not the simulator — system Spotlight behavior differs.
3. **File V2 and V3 the same day** you start. They are the only items with external latency.
4. **Update this file as items resolve.** Change 🔴 to ✅ in the source file, delete the entry here, and note the confirmed signature.
5. **Do not delete any Supabase code until V1 is resolved.** The whole rebuild is contingent on it.
