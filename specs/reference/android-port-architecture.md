# Android Port Architecture — Replicating Memento on Kotlin

**Document type:** Reference architecture + phased execution plan for a
second, first-class Android client
**Companion to:** `memento-2.0-architecture-spec.md` (what the iOS app is),
`frontend-preservation-contract.md` (what must not be lost), `CONSTITUTION.md`
(the non-regression contract this port inherits)
**Derived from:** full audit of `MeetMemento/` at 249 Swift files / 48,658 LOC
plus 93 test files / 18,182 LOC, on 2026-09-12
**Status:** draft for decision — mints `DEC-A0nn` Android decisions, no
`REQ-` IDs (those stay platform-neutral and are cited, not re-minted)

---

## 0. Verdict up front

**Build it native: Kotlin + Jetpack Compose. Not Flutter.**

The reason is structural, not aesthetic. Memento is not an app with some AI in
it — it is an app whose entire value sits in the 18,679 lines under
`Services/`, and nearly every load-bearing line of that touches an OS API with
no portable equivalent: an on-device LLM runtime with streaming and
schema-constrained decoding, sentence embeddings, a streaming ASR engine with
voice-activity detection, a CoreML/ONNX neural vocoder driving a live audio
graph, hardware-backed key storage, an on-device search index, home-screen
widgets, and a watch app.

In Flutter, *all* of that is written in Kotlin behind
`MethodChannel`/`EventChannel` anyway — and then paid for twice: once in
Kotlin, once in the Dart mirror types and the channel protocol between them.
Flutter would buy a shared *presentation* layer for the 21,201 lines of
`Views/` + `Components/`, which is the only part of this app that is cheap to
rewrite and the part most tied to platform idiom — exactly backwards from
where the leverage is.

If cross-platform code sharing is a strategic goal, the right tool is **Kotlin
Multiplatform for the domain layer** (§7), which lets a future iOS refactor
adopt the same retrieval, routing, prompt, safety, and insight logic while each
platform keeps its native UI and its native model runtime. That is the same
seam the iOS app already has — `IntelligenceService` — just made
multiplatform. See §3 for the full comparison and the honest case for the
Flutter variant.

**The second verdict:** the Android port is a **Z0-only product**. Android has
no app-callable equivalent of Private Cloud Compute, so the trust-zone model
loses its Z1 leg entirely (§5.3). This is less of a change than it sounds —
iOS today runs every intent at Z0 via `PCCCapability.sdkUnsupported` — but it
makes the choice of on-device model load-bearing, because there is no
deep-reasoning escape hatch behind it.

---

## 1. What is actually being replicated

| Layer | iOS files | iOS LOC | Port character |
|---|---|---|---|
| `Services/` (incl. Intelligence, Voice, Feedback) | 89 | 18,679 | **Split:** ~60% portable logic, ~40% platform rewrite |
| `Components/` | 73 | 12,255 | Rewrite in Compose, 1:1 by behavior |
| `Views/` | 34 | 8,946 | Rewrite in Compose, 1:1 by behavior |
| `ViewModels/` | 5 | 2,708 | Near-mechanical → Kotlin `ViewModel` + `StateFlow` |
| `Utilities/` + `Utils/` | 20 | 2,768 | Mostly portable pure logic |
| `Models/` | 16 | 1,395 | Mechanical → Kotlin data classes / sealed interfaces |
| `Resources/` (Theme, Typography) | 5 | 1,146 | Token-for-token port, new material system |
| `Intents/` + widgets + watch | 3 | ~400 | Rewrite against different surface APIs |
| **Tests** | 93 | 18,182 | **~70% portable** to JVM unit tests — see §9 |

The single most important structural fact: **exactly one Swift file imports
`FoundationModels`** (verified — `grep -c "^import FoundationModels"` across
the tree returns 1, in `FoundationModelsIntelligenceService.swift`). The
`IntelligenceService` protocol is a real, enforced boundary, and everything
behind it — `ModelRouter`, `EntryRetriever`, `TurnClassifier`, `ReplyChannel`,
`PromptRegistry`, `ContextBudget`, `SafetyRouter`, `InsightEngine` — is pure
Swift with no Apple-framework dependency beyond `Foundation` and
`NaturalLanguage`.

That boundary is what makes this port tractable. Roughly 12,000 lines of the
app's actual intelligence are *algorithm*, not *Apple*. They translate.

---

## 2. Non-negotiables the port inherits

Carried over verbatim from `CONSTITUTION.md` and the preservation contract,
because they are product identity, not iOS implementation detail:

1. **No accounts.** Identity is a locally stored display name (spec 023).
2. **The device is the system of record.** No Memento server holds a journal
   entry (`REQ-PRIV-001`, P2).
3. **Journal content never leaves the device for generation.** On Android this
   hardens: there is no Z1, so it is absolute (§5.3).
4. **One module imports the model runtime.** On Android this becomes
   *structurally* enforceable rather than lint-enforced (§7) — a genuine
   improvement over the Swift arrangement.
5. **Routing is a data table, not scattered conditionals** (`REQ-INT-003`).
6. **Near-zero third-party surface** (spec 021 R6). Android cannot hold this at
   literally zero — see `DEC-A004`.
7. **Safety routes are designed states, not errors.** Crisis, guardrail
   refusal, and hard-policy refusal each have their own presentation and must
   never read as judgment of what the user wrote (spec 026).
8. **Counts never come from the model.** Quantitative answers are computed in
   code and handed to the prompt as facts (spec 045 / 037 rule 3).

---

## 3. Kotlin/Compose vs Flutter, decided against this codebase

| Dimension | Kotlin + Compose | Flutter (Dart UI + Kotlin plugin) |
|---|---|---|
| On-device LLM (LiteRT / MediaPipe / AICore) | Direct Kotlin API, streaming via `Flow` | Kotlin plugin + `EventChannel` per token |
| Embeddings (LiteRT / MediaPipe `TextEmbedder`) | Direct; `FloatArray` stays in-process | Serialize 768-dim vectors across the channel, or keep retrieval in Kotlin too |
| ASR with partial results + VAD | `SpeechRecognizer` + `AudioRecord` in-process | Kotlin plugin; ~50 events/sec crossing the boundary |
| Neural TTS (ONNX Runtime + `AudioTrack`) | Direct; PCM never leaves Kotlin | Must stay in Kotlin; Dart only orchestrates |
| Hardware-backed crypto (Keystore/StrongBox) | Direct | Kotlin plugin |
| On-device index (AppSearch / Room FTS) | Direct | Kotlin plugin |
| Home-screen widget | Glance (Compose) — shares the design system | Not possible in Dart; native Kotlin + a duplicate design system |
| Wear OS | Compose for Wear — shares the design system | Effectively unsupported |
| Material 3 Expressive adoption | First-party, tracks the platform | Flutter's Material lags; adaptations, not adoption |
| Predictive back, edge-to-edge, per-app language | Platform default | Plugin/shim work, chronically behind |
| Third-party surface (spec 021 R6) | Jetpack, first-party | Whole runtime + pub ecosystem |
| Code shared with the existing SwiftUI app | Zero either way | Zero (the Swift app is not going away) |
| Streaming-chat hot path (spec 029/032 latency budgets) | In-process | One serialization hop inside the budget |

**The decisive argument:** Flutter's payoff is one UI codebase for two
platforms. Memento already has a mature, contract-protected SwiftUI front end
(`PRES-001`…`PRES-096`) that nobody is going to delete. So Flutter delivers a
*third* UI codebase to maintain, and it delivers it for the layer where
platform idiom matters most, while the hard 60% of the work stays in Kotlin
regardless.

**When the Flutter variant would be right, honestly:** if the AI ran
server-side (it doesn't), if iOS were also being rebuilt from zero (it isn't),
or if the team were Dart-native with no Kotlin capacity (a reasonable reason to
revisit). If that changes, the boundary is: Dart owns
`Views`/`Components`/`ViewModels`; a single Kotlin plugin named
`memento_intelligence` exposes `IntelligenceService`, `SpeechService`,
`VoicePlaybackService`, and the crypto/store as its entire channel API — the
same seams that exist today. Budget ~30% on top of the native estimate for the
channel layer and the duplicated model types, and accept losing Glance and
Wear.

---

## 4. Android platform baseline (`DEC-A001`)

Following Android platform requirements rather than transliterating iOS:

| Setting | Value | Why |
|---|---|---|
| `compileSdk` / `targetSdk` | 36 (Android 16) | Play's current target-API requirement for updates |
| `minSdk` | **31** (Android 12) | `RenderEffect` blur (the design system needs it), `VibrationEffect.Composition`, splash screen API. 33 if on-device `SpeechRecognizer` is required rather than degraded. |
| Language / build | Kotlin 2.x, K2, Gradle KTS, version catalogs, KSP | — |
| UI | Compose BOM, **Material 3 Expressive** | §6 |
| Async | Coroutines + `Flow`; `StateFlow` for UI state | Replaces Combine / `@Published` |
| DI | Hilt (or Metro/Koin) | Replaces the `.shared` singletons — see `DEC-A002` |
| Persistence | Room + SQLCipher; DataStore for prefs | §5.1 |
| Navigation | Navigation 3 / type-safe routes from a sealed `Route` hierarchy | Ports `Models/Routes.swift` directly |
| Images | Coil 3 | `PhotoThumbnailCache` |
| Required platform behaviors | edge-to-edge (`enableEdgeToEdge()`), predictive back, per-app language (`localeConfig`), photo picker (no storage permission), `POST_NOTIFICATIONS` runtime request, FGS type `microphone` | Android 13–16 requirements |

**`DEC-A002` — kill the singletons on the way over.** The iOS app reaches for
`EncryptionService.shared`, `SpeechService.shared`, `EmbeddingService.shared`.
Android has a hostile process lifecycle (configuration change, process death,
`onTrimMemory`) and these objects own a database key, a mic, and a 300MB
model. Every one becomes a DI-scoped singleton with an explicit lifecycle, not
a lazily-initialized global.

---

## 5. Layer-by-layer replication map

### 5.1 Data layer — SwiftData + CloudKit → Room (+ deferred replica)

`JournalSchema.swift`'s seven `@Model` types port to Room entities almost
mechanically. The CloudKit constraints that shaped them (every property
optional-or-defaulted, no unique attributes, relationships have inverses, enums
stored as raw values) are *good Room hygiene too*, so nothing has to be
redesigned:

| SwiftData | Room |
|---|---|
| `StoredEntry` | `@Entity` + `@ColumnInfo(defaultValue=…)`; `transcript` encrypted at rest |
| `StoredAttachment`, `StoredCitation` | `@Entity` with `ForeignKey(onDelete = CASCADE)` — the literal `.cascade` delete rule |
| `StoredConversation` / `StoredTurn` | `@Entity` + `@Relation` in a `@DataClass` projection |
| `StoredReflection` ↔ `StoredEntry` (many-to-many) | explicit join `@Entity` — Room has no implicit inverse |
| `@Attribute(.allowsCloudEncryption)` | no analog; column-level AES-GCM (§5.2) |
| `healthJSON: Data?` | `@TypeConverter` to JSON via kotlinx.serialization |
| `ModelContext` + `@Query` | `@Dao` returning `Flow<List<…>>` |

**`DEC-A003` — CloudKit has no Android equivalent. Ship Android v1 single-device.**
Options evaluated:

- **Google Drive `appDataFolder`** — the closest structural analog: the user's
  own account, app-private scope, no Memento server. But it needs Google
  Sign-In, which breaks non-negotiable #1 unless framed exactly as iCloud is
  ("your Google account, not a Memento account"), and it is a manual
  sync engine to write, not a mirroring framework.
- **Android Auto Backup** — 25MB cap, restore-on-new-device only, not
  multi-device sync. Useful as a floor, not as `PRES-025`'s sync line.
- **Block Store** (`play-services-auth-blockstore`) — the right home for the
  *DEK* across device transfer, which is the genuinely hard part of any
  backup story. Worth adopting even without full sync.

Recommendation: Room as the only system of record in v1; keep
`SyncStatusStore`'s seam in place emitting `Unsupported`; build Drive
replication as a phase-8 feature behind its own decision record. The passive
sync-status line (`PRES-025`) is device-neutral copy already, so it degrades
honestly.

`LegacyStoreImporter` and `FiveStoreDeletion` have no port — there is no legacy
Android store — but **`FiveStoreDeletion`'s contract does** port: "Delete
Everything" must provably clear entries, photos, embeddings, chat transcripts,
and derived caches. Keep the test, rename the stores.

### 5.2 Security — Keychain/CryptoKit → Keystore/Tink

| iOS | Android |
|---|---|
| Random DEK in Keychain, `…WhenUnlockedThisDeviceOnly` | AES-256 key in **Android Keystore**, `setIsStrongBoxBacked(true)` when available, `setUnlockedDeviceRequired(true)` — the literal semantic match |
| AES-GCM via CryptoKit | `javax.crypto` AES/GCM/NoPadding, or Tink `AesGcmKeyManager` with an Android Keystore master key |
| PIN in Keychain + constant-time compare | PIN **hash** (Argon2id or PBKDF2-SHA256 at ≥100k, matching the current iterations) in an encrypted DataStore; `MessageDigest.isEqual` for the constant-time compare |
| `LocalAuthentication` FaceID/TouchID + device-passcode fallback | `BiometricPrompt` with `BIOMETRIC_STRONG or DEVICE_CREDENTIAL` — one call covers `PRES-070`/`PRES-072` |
| `NSFileProtectionCompleteUntilFirstUserAuthentication` (`REQ-DATA-003`) | File-Based Encryption is the platform default; credential-encrypted storage *is* until-first-unlock. Do **not** use `createDeviceProtectedStorageContext()` for journal data. |
| Auto-lock on `scenePhase` (`PRES-073`) | `ProcessLifecycleOwner` `ON_STOP` + `FLAG_SECURE` on the window so the recents thumbnail doesn't leak the journal — an iOS-invisible requirement |

Add SQLCipher for whole-database encryption, keyed by the Keystore DEK, so the
port doesn't have to replicate per-field encryption decisions that only existed
because CloudKit mirroring forbade the `ThisDeviceOnly` DEK.

### 5.3 Trust zones — the honest Android answer

`TrustZone.swift` has three cases: `z0Device`, `z1AppleContent(reasoningLevel:)`,
`z1AppleContentFree`. On Android:

- **`Z0Device` stays**, and becomes the only content zone.
- **`Z1` has no Android equivalent.** Private Compute Core is a system sandbox
  for Android System Intelligence, not a generation service an app can call.
  The Gemini API via Firebase AI Logic is an ordinary cloud service — Z2 by
  Memento's own definitions — and `REQ-PRIV-001` forbids journal content going
  there. So the enum becomes `Z0Device` and `Z1VendorContentFree` (the
  WeatherKit-shaped case: a network call carrying no journal content).
- **`ModelRouter` ports unchanged**, with `PCCCapability` permanently
  `sdkUnsupported` and a new `RouteReason.platformHasNoAttestedCloud`. The
  routing table keeps one row per intent, `degradedZone` is structurally `null`
  everywhere, and `ModelRouterTests`' walk-every-case invariant still holds.
- **Consequence:** the Z0 model quality *is* the product ceiling. This is the
  single biggest argument for `DEC-A004` below.
- The `PRES-087` "On-Device Only" toggle becomes informational rather than
  functional. Do not delete the switch silently — either keep it as a
  read-only "Always on this device" row, or hide it and keep
  `processOnDeviceOnly` pinned true in the router.

### 5.4 The intelligence boundary — the real work

`IntelligenceService` (a 470-line protocol) ports to a Kotlin interface with
almost no shape change; `AsyncThrowingStream<AskStreamEvent, Error>` becomes
`Flow<AskStreamEvent>`, and `GenerationOutcome<T>`/`AskResult` become data
classes. What has to be *built* is the thing behind it.

**`DEC-A004` — bring your own model; treat Gemini Nano as an accelerator.**

| Option | Coverage | Control | Verdict |
|---|---|---|---|
| **ML Kit GenAI** (Summarize / Rewrite / Proofread / Image Description) | Broad on supported devices | None — fixed task APIs, no free-form prompting | **Unusable.** Memento's prompts are the product. |
| **Gemini Nano via AICore** (`com.google.ai.edge.aicore`) | Flagships only (Pixel 9+, Galaxy S24+ class) | Prompt + streaming; no schema-constrained decoding; no LoRA | **Opportunistic second leg.** Same availability story Apple FM has, and the same graceful-degradation UI already exists. |
| **LiteRT-LM / MediaPipe `LlmInference`** with Gemma 3 1B int4 (~530MB) or Gemma 3n E2B | Any device with ~4GB RAM — *wider than Apple Intelligence* | Total: streaming, LoRA, function calling, temperature/topK, model pinning | **Primary.** |
| **Firebase AI Logic hybrid** | — | Cloud fallback | **Rejected** — the fallback is Z2 with journal content. |

The inversion is worth naming: on iOS, availability is Apple's to grant and the
app degrades where Apple Intelligence is absent. On Android, the app can
*guarantee* its own model on nearly any device — at the cost of shipping
weights. That trade favors Memento, because a journaling app whose AI silently
isn't there on most devices is not a product.

**`DEC-A005` — guided generation is the hardest single gap.** The iOS service
leans on `@Generable`/`@Guide` at fourteen call sites: `AskReply`,
`ProfileEstimate`, `ConversationSummary`, `EntryReflection`,
`PeriodReflection`, the `SearchJournalTool` arguments. Apple's constrained
decoding makes malformed output *structurally impossible* and hands back a
typed value. Android has no OS-level equivalent. Three tiers, in order of
preference:

1. **Grammar-constrained decoding in the runtime** — a GBNF/JSON-schema
   grammar compiled into the sampler (llama.cpp-family runtimes, ONNX Runtime
   GenAI's guidance support). Same guarantee Apple gives, at the cost of a
   heavier runtime choice. **Spike this first (Phase 0) — it decides the runtime.**
2. **Structured-output / function-calling mode** where the chosen runtime
   offers it (MediaPipe's function-calling SDK), which constrains shape but not
   always strictly.
3. **Schema-in-prompt + tolerant parser + bounded repair retry.** The fallback,
   and the app is unusually well-prepared for it: `RichTextParser` (456 lines),
   `ChatResponseDecodingTests`, and the "JSON never shown raw" rule in
   `PRES-042` all exist *because* the pre-2.0 server era had exactly this
   problem. Port that machinery rather than assuming it away.

Whichever tier lands, the port needs one new component the iOS app doesn't
have: a `GuidedDecoder<T>` in `intelligence:runtime` that owns schema → prompt
fragment → parse → repair → typed value, so the fourteen call sites keep
looking like `@Generable` call sites and no feature code learns about JSON.

**What ports essentially as-is** (pure logic, JVM-testable, no Android API):
`ModelRouter`, `QuotaGovernor`, `TurnClassifier` (472 lines), `ReplyChannel`,
`RetrievalPolicy`, `SearchJournalPolicy`, `PromptRegistry` (720 lines — the
prompt text is data), `ContextBudget`, `PassageChunker`, `QueryDateWindow`,
`QuotedSpanExtractor`, `AskTranscriptPlan`, `TurnShapeCadence`,
`ConversationalMove`, `ComputedFactsBlock`, `InsightEngine` + `InsightFact`
(the Swift-computed arithmetic from spec 045), the whole `Safety/` package,
`StreamingSentenceChunker`, `RefusalOutageTracker`, `ExperienceProfileBuilder`.
That is roughly 8–9k lines of Swift→Kotlin transliteration — tedious, low-risk,
and directly covered by ported tests.

`ModelRuntimeGate` (the watchdog that turns a silent model into
`generationTimedOut`) matters *more* on Android, where thermal throttling and
`onTrimMemory` model eviction are real. Port it and widen it: add an explicit
`modelEvicted` reason.

### 5.5 Retrieval + embeddings — an upgrade, not a port

`EmbeddingService` (719 lines) is built on `NLEmbedding`, whose absolute
cosines "run hot" — the reason `RetrieverTuning` scores against μ + k·σ of the
corpus rather than an absolute threshold. Android's replacement is genuinely
better:

| iOS | Android |
|---|---|
| `NLEmbedding.sentenceEmbedding(.english)`, word-embedding fallback, keyword degradation | **EmbeddingGemma-300M** via LiteRT (768-dim, Matryoshka-truncatable to 128, built for on-device RAG), or MediaPipe `TextEmbedder` as the light option |
| `Accelerate` dot products | `FloatArray` + a small SIMD-friendly loop, or LiteRT's own op |
| Per-entry `.vec` files under Application Support, atomic writes, file protection, FNV-1a content hashing | Same design, same FNV-1a hash (never `hashCode()` — also unstable), in app-private storage inside the SQLCipher DB or encrypted files |
| In-memory + disk two-tier cache, passage-level reuse on edit | Port as-is; it is good design independent of platform |

Because the embedder changes, **`RetrieverTuning`'s constants do not transfer**
— `semanticFloorAbs = 0.30`, `sigmaK = 1.0`, `keywordSignalMin = 2.0` were
measured against `NLEmbedding`'s distribution. They must be re-tuned against
the new embedder using the existing fixture corpus, and the μ+kσ *design* is
what makes that re-tuning cheap. Treat the tuning pass as scoped work in Phase
3, with `Fixtures/` and the `Diag*` eval harnesses as the instrument.

Retrieval itself (`EntryRetriever`, 970 lines of hybrid semantic + keyword +
recency ranking with ambient fallback) is pure logic and ports directly.
`EntrySpotlightIndexer` maps to **AppSearch** (`androidx.appsearch`) if
system-search surfacing is wanted, or to **Room FTS4** if it isn't — and note
that the Core Spotlight privacy question (`DEC-002`: can donation be hidden
from system-wide search?) has a cleaner Android answer, since AppSearch
documents are app-scoped unless explicitly shared with the system.

### 5.6 Voice in — SpeechAnalyzer → SpeechRecognizer + VAD

`SpeechAnalyzerEngine` (294 lines) uses the iOS 26 `SpeechAnalyzer` /
`SpeechTranscriber` / `SpeechDetector` trio plus `AssetInventory` for locale
model download.

| iOS | Android |
|---|---|
| `SpeechAnalyzer` + `SpeechTranscriber`, volatile + finalized segments | `SpeechRecognizer.createOnDeviceSpeechRecognizer()` (API 33+) with `EXTRA_PARTIAL_RESULTS`; `onPartialResults` ≈ volatile tail, `onResults` ≈ finalized |
| `SpeechDetector` VAD (spec 034 barge-in) | **No public VAD.** Ship Silero VAD (ONNX, ~2MB) or WebRTC VAD alongside the RMS gate the app already computes |
| `AssetInventory` locale download + `assetState` | Recognition-service-managed; expose `LanguageDetailsChecker` / `checkRecognitionSupport()` into the same `TranscriptionAssetState` enum |
| `AVAudioEngine` tap, 20Hz RMS hop to MainActor | `AudioRecord` on a dedicated thread, RMS hop to a `StateFlow` at the same 20Hz — the reason for that hop (`PRES-024`: don't re-render the backdrop 50×/sec) applies identically in Compose |
| Long-dictation durability | **Foreground service, type `microphone`**, with a Live Update notification — an Android requirement with no iOS counterpart |

If `SpeechRecognizer`'s on-device quality doesn't hold up for long reflective
dictation (the app allows a *20-second* silence timeout — unusually generous,
and a real stress test), the fallback is Whisper-small via LiteRT/ONNX. Spike
it in Phase 0; it is a plausible outcome, not a remote one.

### 5.7 Voice out — Supertonic CoreML → Supertonic ONNX

This is the port's pleasant surprise. `Packages/SupertonicTTS` is a vendored
fork of `soniqo/speech-swift` running four CoreML graphs (TextEncoder,
DurationPredictor, VectorEstimator, Vocoder) with a bundled unicode indexer —
and upstream (`supertone-inc/supertonic`, MIT) publishes the **same graphs in
ONNX**. So:

- Runtime: **ONNX Runtime Mobile** (`onnxruntime-android`) with NNAPI/QNN
  execution providers, or convert to `.tflite`/LiteRT.
- `SupertonicTokenizer` + `unicode_indexer.json` port as pure Kotlin — and
  critically, the fork's defining property (**G2P-free**, hence no
  GPL-contaminated text path, `REQ-TTS-009`) survives.
- Audio out: `AudioTrack` in streaming mode, replacing `AVAudioEngine`.
  `TTSPlayback`, `TurnStartMask`, `ConversationAudioController` (full-duplex,
  spec 034) and `VoicePlaybackService` (848 lines) port as logic over that.
- `SystemUtteranceEngine` → Android `TextToSpeech`, the graceful baseline.
- **Personal Voice has no Android equivalent.** Drop it; the `VoiceCatalog`
  already models multiple voices, so it's a catalog entry that isn't there.
- `AudioFocusRequest` and `AudioAttributes` are mandatory on Android and have
  no iOS analog — full-duplex conversation must handle focus loss (a call, a
  navigation prompt) as a first-class state.

**`DEC-A006` — the 148MB of vendored weights cannot ship in the base module.**
Spec 030 R1 forbids model-download code, and iOS honors that by compiling the
weights into the signed binary. Play caps the base download at ~200MB, and the
LLM adds another ~530MB on top. So Android must use **Play Asset Delivery**
(install-time or fast-follow asset packs). This is a real divergence from spec
030 R1 as written, and it should be recorded rather than finessed. The *spirit*
survives: PAD is first-party, Play-served, signed, and integrity-checked — the
thing R1 exists to prevent is an app-authored HuggingFace hub client, and PAD
is not that. OpenRAIL-M attribution (`DEC-010`) still applies and belongs in
`AcknowledgmentsView`'s Android twin.

### 5.8 Presentation — SwiftUI → Compose

MVVM survives intact. `ObservableObject` + `@Published` → `ViewModel` +
`StateFlow`; `@MainActor` → `Dispatchers.Main.immediate`; `Task` → `viewModelScope`;
`AsyncThrowingStream` → `Flow`. `ChatViewModel` (1,181 lines) is the biggest
single translation and the most valuable one to do faithfully: its streaming
delta coalescing, `SendTicket`, `transcriptGeneration` guard, and per-message
retry state are hard-won (`PRES-047`, spec 010).

Mapping the specific hard parts:

| iOS | Compose |
|---|---|
| `NavigationStack` + route enums (`PRES-011`) | Navigation 3 with the same sealed `Route` hierarchy — deep-link surface for widgets/App Functions preserved |
| `RootPager` two-page swipe + commit haptic (`PRES-004`) | `HorizontalPager`; haptic via `LocalHapticFeedback` / `VibrationEffect.Composition` |
| `EntryEditorPager` (`TabView(.page)`, commit-on-swipe) (`PRES-023`) | `HorizontalPager` with the same commit-not-discard semantics |
| Native zoom transition editor morph (`PRES-023`) | **Shared-element transitions** (`SharedTransitionLayout` + `sharedBounds`) — the closest equivalent; the "morph over the live root page, never a blank plate" constraint is the part to protect |
| `matchedGeometryEffect` | `sharedElement` |
| Typewriter reveal ~120cps (`PRES-042`) | Coroutine-driven `AnnotatedString` slice — cheap and better in Compose |
| `LazyVStack` month sections (`PRES-020`) | `LazyColumn` + `stickyHeader` |
| Progressive blur edges (`PRES-094`/`PRES-095`) | `Modifier.graphicsLayer` + `RenderEffect.createBlurEffect` with a gradient mask (API 31+) |
| `GlassEffectContainer` / `.glassEffect` (`PRES-092`) | **Do not reimplement Liquid Glass.** See §6. |
| Dynamic Type via `relativeTo:`/`ScaledMetric` (`PRES-091`) | `sp` units + Android 14 non-linear font scaling; test at 200% |
| Haptic vocabulary (`PRES-093`) | `HapticFeedbackConstants` (`CONFIRM`/`REJECT`/`SEGMENT_TICK`, API 34+) with `VibrationEffect` fallbacks — coarser than Core Haptics; budget a tuning pass |
| Video welcome background (`PRES-060`) | `ExoPlayer`/Media3 looping, no audio focus |

### 5.9 Surfaces and system integration

| iOS | Android |
|---|---|
| `MementoAppIntents` | **App Functions API** (`androidx.appfunctions`, Android 16) for Gemini/Assistant, plus `ShortcutManagerCompat` dynamic shortcuts |
| Lock-screen widget (`MementoLockWidgetView`) | **Glance** app widget (home screen). Phone lock-screen widgets don't exist; substitute a **Quick Settings tile** for "new entry" / "start dictation" |
| Live Activity (recording) | **Live Updates** (Android 16 `Notification.ProgressStyle`) + the mic foreground service |
| Watch app (`MeetMementoWatch`) | Compose for Wear OS + a Tile |
| Core Spotlight donation | AppSearch (or nothing — see §5.5) |
| Journaling Suggestions picker (`ATTACH-10`) | **No equivalent.** Substitute app-authored starters from `ThemeAwareChatStarters`, which already exists |
| Two notifications (daily reminder, weekly ready) | `WorkManager` + `POST_NOTIFICATIONS`; note Android's aggressive Doze/App Standby — use `setExactAndAllowWhileIdle` sparingly and design for late delivery |
| `BGProcessingTask` Sunday weekly reflection (spec 019 R8) | `WorkManager` periodic work with constraints (charging + idle) — **better** than iOS's opportunistic scheduler |
| StoreKit / RevenueCat (`ATTACH-07`) | Play Billing 7 (RevenueCat has an Android SDK if the abstraction is wanted) |
| App Store privacy nutrition label ("Data Not Collected") | **Play Data Safety form** — same claim, and the opt-in feedback path (spec 042) is the same thing that can break it |
| `SupabaseFeedbackClient` (opt-in, write-only RPC) | Ktor or Retrofit against the same RPC; the consent gate, `FeedbackOutbox`, and device-identity logic port as-is |

---

## 6. Design system — do not port Liquid Glass

`PRES-090`/`PRES-091` port cleanly and should be treated as canonical: the
gray/primary/brand hex scales, the measured WCAG ratios, the radius scale, the
emotion colors, and both typefaces. Figtree, Lora, Manrope and Sora are all
Google Fonts under OFL — they drop straight into `res/font` (or Compose
downloadable fonts) and the h1–h6/body/caption scale transfers with `sp` units.
`Theme.swift`'s `light`/`dark` structs become a Compose `ColorScheme` pair plus
a `MementoTheme` `CompositionLocal` for the non-Material tokens.

`PRES-092` is the one part that must **not** be replicated. Liquid Glass is an
iOS 26 material with system-level backdrop refraction; Android's equivalent
idiom is **Material 3 Expressive** — tonal elevation, surface containers, shape
morphing, spring-based motion. Faking frosted glass on Android produces an
uncanny app that is also slow: real backdrop blur needs capturing the layer
beneath (`rememberGraphicsLayer` + `record`, or `RenderEffect` chains), and
`PRES-023`'s own hard-won note says a screen-sized live filter under five glass
surfaces stalled the *device* while looking fine in the Simulator. Android's
GPU budget is wider and shallower.

So: translate the *intent* of each glass rule, not the material.

| Glass rule (`PRES-092`) | Android translation |
|---|---|
| Chrome floats, content passes under it and blurs into it (`PRES-095`) | Edge-to-edge with `Modifier.blur`-masked scrim bands over a `LazyColumn`; never an opaque slab |
| One `GlassEffectContainer` per adjacent cluster | One `Surface` per cluster at a consistent tonal elevation |
| Theme-backed chrome stays untinted so the system adapts | Material You dynamic color is **off** for chrome — Memento's brand palette is the identity (`PRES-090`); consider offering dynamic color as an Appearance option only |
| Photo-backed chrome may carry a backdrop-derived wash for legibility (`JournalBackdropContrast`) | Port directly — Palette/`Palette.from(bitmap)` or the existing contrast math over the decoded thumbnail; this rule is platform-neutral and load-bearing for the photo editor |
| Never an opaque fill beneath glass | Never an opaque scrim beneath a blur band — same defect, same fix |
| No private API (`PRES-096`) | Same rule, same teeth: no reflection into `CABackdropLayer` equivalents, no hidden-API access (Android blocks it anyway, and Play flags it) |

`PRES-023`'s device-performance note is the single most transferable piece of
hard-won knowledge in the contract: the backdrop layer carries no animated
transform and no per-frame filter rebuild, neighbours load the decoded
thumbnail and defer full-resolution decode until the page is active. Bake that
into the Compose editor from day one rather than rediscovering it.

---

## 7. Module structure — making the boundary structural

Gradle modules let Android enforce what Swift enforces by convention. This is a
real upgrade over the iOS arrangement, where "exactly one file imports
`FoundationModels`" is a review rule.

```
memento-android/
├── app/                         # Application, DI graph, NavHost, MainActivity
├── core/
│   ├── model/                   # Entry, ChatTurn, TrustZone, GenerationIntent…
│   ├── design/                  # Theme, Typography, motion, haptics, M3E surfaces
│   ├── common/                  # Result, Clock, dispatchers, logging (content-free)
│   └── testing/                 # fixtures, fakes, the ported Fixtures/ corpus
├── data/
│   ├── database/                # Room entities, DAOs, migrations
│   ├── crypto/                  # Keystore DEK, AES-GCM, SQLCipher
│   ├── prefs/                   # DataStore (PreferencesService, AppStateStore)
│   ├── photos/                  # PhotoStorage, thumbnail cache
│   ├── export/                  # Markdown/JSON export (ATTACH-06)
│   └── replica/                 # phase 8 — Drive appDataFolder
├── intelligence/
│   ├── api/                     # IntelligenceService + envelopes — NO runtime dep
│   ├── prompts/                 # PromptRegistry, versioned prompt text
│   ├── routing/                 # ModelRouter, QuotaGovernor, ModelRuntimeGate
│   ├── retrieval/               # EntryRetriever, PassageChunker, ContextBudget
│   ├── embedding/               # EmbeddingService iface + LiteRT impl
│   ├── classify/                # TurnClassifier, ReplyChannel, RetrievalPolicy
│   ├── insights/                # InsightEngine, InsightFact
│   ├── safety/                  # SafetyRouter, classifier, scanner, crisis JSON
│   └── runtime/                 # ★ the ONLY module that may depend on the LLM runtime
├── voice/
│   ├── asr/                     # SpeechRecognizer + VAD + AudioRecord
│   ├── tts-api/
│   └── tts-supertonic/          # ★ the ONLY module that may depend on ONNX Runtime
├── feature/{journal,chat,onboarding,lock,settings,insights}/
├── widget/                      # Glance widgets + QS tile
├── wear/
└── benchmark/                   # macrobenchmark + baseline profiles
```

Two `★` modules, two enforced invariants. Add a Gradle dependency-graph
assertion to CI so a feature module that reaches for the runtime **fails the
build** — the Android analog of `spec-gates.yml`, and strictly stronger than
what the Swift target can do.

**The KMP option.** If sharing with iOS ever becomes the goal, the modules to
make multiplatform are exactly `core:model`, `intelligence:api`,
`intelligence:{prompts,routing,retrieval,classify,insights,safety}` — the ~9k
lines that are already platform-free on both sides. Each platform keeps its
own `intelligence:runtime` (FoundationModels on iOS, LiteRT on Android), its own
store, and its own UI. That is the version of "cross-platform" that would
actually pay, and it is a strictly better destination than Flutter for this
codebase. Don't do it in v1 — build Android native first, then extract.

---

## 8. Phased plan

Sized in the repo's own "session" unit (one focused implementation session,
2–3 for larger specs), so it composes with `ROADMAP.md`.

| Phase | Scope | Sessions | Exit gate |
|---|---|---|---|
| **0 — Derisk** | Four spikes, no product code: (a) LLM runtime bake-off with **grammar-constrained decoding as the pass/fail criterion** (`DEC-A005`); (b) EmbeddingGemma vs MediaPipe TextEmbedder on the `Fixtures/` corpus, retuning `RetrieverTuning`; (c) Supertonic ONNX on `AudioTrack` — first-audio latency vs spec 032's budget; (d) `SpeechRecognizer` on-device quality for 60s+ reflective dictation | 3–4 | Four written decision records. Any spike that fails picks its fallback *now*, not in Phase 3. |
| **1 — Foundations** | Gradle/modules/DI, design system port (`PRES-090`/`091` + §6), Room schema + SQLCipher + Keystore, PIN/biometric lock (`PRES-070`…`074`), navigation + routes, `FLAG_SECURE`, edge-to-edge | 5–6 | Locks, unlocks, persists an entry. Golden-image tests on the token system. |
| **2 — Journal loop** | Timeline + month sections + picker, editor (`PRES-023` incl. shared-element morph and the device-performance rules), photo cover + treated backdrop, search, toast, export, Delete Everything | 6–8 | `PRES-020`…`026` verified. The app is a usable private journal with zero AI. |
| **3 — Intelligence core** | `intelligence:runtime` + `GuidedDecoder`, embeddings + two-tier cache, retriever + retuned constants, classifier/channels/policy, `PromptRegistry`, router, safety package, `ModelRuntimeGate` | 9–11 | Ported logic tests green; eval harness reproduces iOS grounding numbers within an agreed band. |
| **4 — Chat surface** | `ChatViewModel` + streaming coalescing, three-state composer (`PRES-041`), message rendering + typewriter + rich-text parser (`PRES-042`), citations sheet (`PRES-044`), feedback bar (`PRES-043`), history (`PRES-045`), summarize-to-entry (`PRES-046`), failure/gating states (`PRES-047`/`048`) | 7–9 | `PRES-040`…`048` verified end to end. |
| **5 — Voice** | ASR + VAD + mic foreground service + Live Update, dictation pill (`PRES-024`), Supertonic engine + `AudioTrack` streaming, narration mode, full-duplex + audio focus, spoken-form formatter | 7–9 | Dictate a long entry; hear a reply; barge in; survive an incoming call. |
| **6 — Insights** | `InsightEngine` + entry tagging at save (`ATTACH-04`), weekly reflection + `WorkManager` scheduling (`ATTACH-02`), Patterns surface (`ATTACH-03`), quantitative Ask | 4–5 | Weekly reflection generates unattended overnight. |
| **7 — Surfaces** | Glance widget, QS tile, App Functions + shortcuts, notifications + prefs, Wear OS + Tile, Play Billing if monetizing | 4–6 | Deep links land on the right route from every surface. |
| **8 — Ship readiness** | TalkBack + 200% font pass, macrobenchmark + baseline profiles, Play Asset Delivery packaging (`DEC-A006`), Data Safety form, Play Console setup, optional Drive replica (`DEC-A003`) | 5–6 | Internal-testing track build that passes review. |

**Total: 50–64 sessions.** For one experienced Android engineer full-time,
roughly **3–4 months**; at a learning pace alongside the iOS app, plan
**6–9 months**. The honest shape of the risk is front-loaded: Phase 0 and
Phase 3 carry nearly all of it, and Phases 1–2 are the least risky work in the
whole program. Resist the temptation to start at Phase 3 because it's the
interesting part — Phase 0's four answers change what Phase 3 even builds.

**Suggested first slice if you want something running this week:** Phase 1's
design system + Room + a read-only timeline off seeded fixtures. It proves the
token port, the Compose idiom, and the schema against real data, and it is the
part where your front-end instincts transfer directly.

---

## 9. Tests and CI

The 18,182 lines of tests are an asset, and most of them move.

- **Portable (~70%)** — `ModelRouterTests`, `AskPromptContractTests`,
  `AskPromptSizeTests`, `TurnClassifier*`, `ContextBudgetTests`,
  `ConversationSummaryTests`, `ChatResponseDecodingTests`,
  `ConversationalRecallContractTests`, the retrieval and insight suites, the
  safety suites. These test pure logic and become JVM unit tests (JUnit5/Kotest,
  Turbine for `Flow`). Port them *with* the code, in the same session — they are
  the only thing that will tell you a 400-line transliteration is faithful.
- **Re-authored** — anything asserting SwiftUI behavior: Compose UI tests, plus
  Roborazzi/Paparazzi screenshot tests for the token system and the glass→M3E
  translation. Screenshot tests earn their keep here more than on iOS, because
  §6 is a redesign and you need to see drift.
- **Eval harness** — `DiagGroundingEval`, `DiagLatencyProfile`,
  `DiagHistoryDepth` and the `Fixtures/` corpus port as instrumented tests and
  become the Phase 0 / Phase 3 tuning instrument. Keep the numbers comparable to
  iOS so a regression is legible across both clients.

**The CI story is meaningfully better than iOS.** The iOS app needs
self-hosted macOS runners and a physical Apple Intelligence device for live
generation (`ios-device-eval.yml`), so model behavior is tested *out of band*.
On Android, a LiteRT/MediaPipe model runs on an **x86 emulator on CPU** in a
hosted GitHub runner — so on-device generation, retrieval quality, and the
guided-decode contract can all sit in the merge lane. Gemini Nano/AICore still
needs physical devices (Firebase Test Lab), but it's the optional second leg,
not the baseline. Mirror the three merge lanes (`build`, `security`,
`spec-gates`) with Gradle equivalents, and add the module-graph assertion from
§7 to `spec-gates`.

---

## 10. What changes, and must be said out loud

Not everything survives the crossing. These are product decisions, not
implementation details, and each needs an owner:

1. **No multi-device sync in v1** (`DEC-A003`). CloudKit has no analog. The
   sync-status line degrades honestly; Drive replication is phase 8 at the
   earliest.
2. **No Z1 / no Private Cloud Compute** (§5.3). Every intent runs on device.
   The "On-Device Only" toggle loses its job.
3. **No Personal Voice.** One fewer voice in the catalog.
4. **No Journaling Suggestions.** App-authored starters instead.
5. **No lock-screen widget on phones.** A Quick Settings tile is the substitute.
6. **Model weights ship via Play Asset Delivery, not inside the binary**
   (`DEC-A006`) — a documented divergence from spec 030 R1.
7. **Retrieval constants are re-derived, not copied** (§5.5). The μ+kσ design
   survives; the numbers don't.
8. **Guided generation is reconstructed, not inherited** (`DEC-A005`). This is
   the port's central technical risk and the thing Phase 0 exists to settle.
9. **The third-party surface grows from zero.** ONNX Runtime (or LiteRT),
   SQLCipher, Coil, and the model weights all need spec 021 R6 decision records.
   Zero is not achievable on Android; "small, first-party-where-possible,
   each one recorded" is.
10. **Haptics will feel coarser.** `PRES-093` calls the haptic vocabulary "part
    of the product feel." Android's primitives are blunter. Budget a tuning
    pass rather than discovering it in review.

---

## 11. Open decisions

| ID | Question | Settled by |
|---|---|---|
| `DEC-A001` | `minSdk` 31 or 33? 33 gets on-device `SpeechRecognizer` unconditionally; 31 gets ~8% more devices with a degraded ASR path | Phase 0 spike (d) + install-base data |
| `DEC-A002` | Hilt, Metro, or Koin | Phase 1, low stakes |
| `DEC-A003` | Multi-device replication: Drive `appDataFolder`, Auto Backup floor, or single-device v1 | Product; recommend single-device v1 + Block Store for the DEK |
| `DEC-A004` | Primary model: Gemma 3 1B int4, Gemma 3n E2B, or something else — and whether Gemini Nano is a real second leg | Phase 0 spike (a) |
| `DEC-A005` | Guided-generation tier: grammar-constrained sampler, structured-output mode, or parse-and-repair | Phase 0 spike (a) — **decides the runtime** |
| `DEC-A006` | Asset delivery: install-time pack (bigger install, always present) vs fast-follow (smaller install, a first-run window with no AI) | Product + Play limits |
| `DEC-A007` | AppSearch vs Room FTS for the local index, and whether anything is surfaced to system search | Phase 2/3 |
| `DEC-A008` | Material You dynamic color: off entirely, or offered as an Appearance option beside System/Light/Dark (`PRES-080`) | Design |
| `DEC-A009` | Does the Android client share the spec-numbering namespace, or carry its own `A0nn` series | Process |

---

## 12. The one-paragraph version

Port native in Kotlin and Compose. The app's intelligence — routing,
retrieval, classification, prompts, safety, insights, roughly 9,000 lines — is
already platform-free Swift behind a single enforced interface, and it
transliterates with its tests intact. Replace four Apple frameworks with four
Android equivalents, of which three are straightforward (Room+Keystore for
SwiftData+Keychain, `SpeechRecognizer`+VAD for `SpeechAnalyzer`, ONNX Runtime
for CoreML on the *same* Supertonic graphs) and one is the real project:
Apple's Foundation Models with guided generation has no OS-level Android
counterpart, so Memento brings its own model via LiteRT and rebuilds
schema-constrained decoding as an explicit component. Accept that Android is a
Z0-only, single-device product in v1, translate Liquid Glass into Material 3
Expressive rather than imitating it, and let Gradle modules turn the
"one module imports the model runtime" rule into something the build enforces.
Spike the four unknowns before writing product code; the plan after that is
about fifty focused sessions.
