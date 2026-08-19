# 13 — Neural TTS on CoreML (Supertonic 3)

> **ADDED 2026-08-18** for the `030`–`036` neural-voice spec family. This file is
> the API-truth layer for a **second** synthesis path that runs alongside — not
> instead of — the `AVSpeechSynthesizer` path documented in
> `06-speech-and-audio.md` Part B.
>
> Read `06-speech-and-audio.md` §B1 first. Its complete-text constraint is still
> ✅ VERIFIED and still binding **on `AVSpeechSynthesizer`**. It is a property of
> that class, not of speech synthesis, and this file is the evidence for that
> distinction.

**Framework claims below were swept against the iOS 27.0 SDK (27A5228h) on
2026-08-18** — the same SDK build the rest of this library cites. Claims about
Supertonic 3 itself are third-party and are **not** SDK-checkable; they carry 🔴
until measured on a device.

---

## 1. What Supertonic 3 is

🟡 **Repository metadata verified 2026-08-18** (Hugging Face + GitHub APIs).
Model behaviour claims remain 🔴 until measured on a device.

A 99M-parameter, non-autoregressive flow-matching TTS model outputting 44.1 kHz
mono Float32 PCM. Voices are **precomputed style vectors** (small JSON) fed to
one shared model — a voice is data, not a model.

### The four graphs, by their real names

The CoreML export contains these, **not** the names the first draft of this
family used:

| Actual graph | Weights (FP16) | Draft called it |
|---|---|---|
| `TextEncoder.mlpackage` | 34.4 MB | "text_to_latent" |
| `DurationPredictor.mlpackage` | 1.7 MB | "duration" |
| `VectorEstimator.mlpackage` | **243.5 MB** | "autoencoder" (wrong — this is the flow-matching estimator) |
| `Vocoder.mlpackage` | 48.3 MB | "vocoder" |

Plus `config.json`, `tts.json`, `unicode_indexer.json`, and `voice_styles/*.json`.

**`VectorEstimator` is 73% of the bundle and is the graph that runs iteratively**
(flow matching integrates over steps). It — not `TextEncoder` — is the graph
whose ANE residency actually decides latency, which corrects where V29 and
`DEC-008` should point.

### Measured size — 331 MB, over the escalation threshold

Total of the FP16 CoreML bundle, summed from the repository tree
(2026-08-18): **331.47 MB**. Spec `030` R7 sets an escalation threshold at
250 MB, so **this triggers escalation** and is an open product decision, not a
settled input.

### Ten voices ship, not four

`voice_styles/` contains **F1–F5 and M1–M5**. Spec `030` R3's four-voice roster
is a *product selection* from ten, and `DEC-009`'s swap pool is correspondingly
larger than the family's first draft assumed.

### The upstream is NOT archived — corrected 2026-08-18

The family was written on the premise that Supertone had archived the project and
that weights were orphaned. **That premise is false.** Verified against the
GitHub API on 2026-08-18:

| Repo | archived | last push | stars | licence |
|---|---|---|---|---|
| `supertone-inc/supertonic` | **false** | 2026-07-24 | 13,691 | **MIT** |
| `soniqo/speech-swift` | **false** | 2026-08-17 | 1,122 | **Apache-2.0** |

Both are actively maintained; `speech-swift` was pushed the day before this
check. Note also that `speech-swift` is **Apache-2.0**, not MIT as the family's
dependency notes claimed.

This weakens — it does not remove — the vendoring argument. Pinning an exact
commit and vendoring a fork is still sound practice for a dependency this
load-bearing, but it should now be justified as ordinary supply-chain hygiene
rather than as rescue of an abandoned project. Anywhere this family says
"archived upstream", read it as **corrected**.

### The CoreML export is a community conversion

`aufklarer/Supertonic-3-CoreML-FP16` (licence `openrail`, 459 downloads,
last modified 2026-06-24) is **not** published by Supertone. Supertone's own
repo ships **ONNX** (`onnx/{text_encoder,duration_predictor,vector_estimator,vocoder}.onnx`),
not CoreML.

So the real supply-chain choice is: trust a third-party conversion with modest
usage, or **convert from Supertone's official ONNX ourselves** and control the
export. The second is more work and materially better provenance for a model
that will be embedded in a privacy-positioned product — and it is the only option
that lets us choose precision and shapes deliberately (which `DEC-008` may
require anyway). Recorded as an open decision for spec `030`.

### Properties that still matter and still hold

1. **It accepts arbitrary text per call** — nothing requires the complete
   document, so it can be driven chunk-by-chunk from a streaming reply. This is
   the entire reason the family exists.
2. **It is G2P-free** — text is NFKD-normalized and mapped through a Unicode
   index table (`unicode_indexer.json` is right there in the bundle). No
   espeak-ng, no phonemizer, no lexicon. This is the structural reason it clears
   `018` R12 / `REQ-TTS-009`.

---

## 2. Loading a CoreML model and asking for the Neural Engine

✅ **VERIFIED** — `CoreML.framework/Headers/MLModelConfiguration.h`, iOS 27.0
SDK (27A5228h), 2026-08-18.

```objc
typedef NS_ENUM(NSInteger, MLComputeUnits) {
    MLComputeUnitsCPUOnly = 0,
    MLComputeUnitsCPUAndGPU = 1,
    MLComputeUnitsAll = 2,
    MLComputeUnitsCPUAndNeuralEngine API_AVAILABLE(ios(16.0)) = 3
} API_AVAILABLE(ios(12.0));

@property (readwrite) MLComputeUnits computeUnits;                    // MLModelConfiguration
@property (readwrite, copy, nonatomic) MLOptimizationHints *optimizationHints;  // ios(17.4)
```

**`.all` is a request, not a guarantee.** Core ML segments the graph and places
each segment where it judges best; ANE residency is an outcome you *measure*,
never an outcome you *declare*. `MLComputeUnitsCPUAndNeuralEngine` (3) excludes
the GPU but still does not force the ANE.

Two hints exist and are directly relevant to a variable-length text-to-latent
graph — ✅ VERIFIED, `MLReshapeFrequencyHint.h` / `MLSpecializationStrategy.h`:

```objc
typedef NS_ENUM(NSInteger, MLReshapeFrequencyHint) {
    MLReshapeFrequencyHintFrequent   = 0,   // default — minimize per-shape-change latency
    MLReshapeFrequencyHintInfrequent = 1,   // re-optimize per shape; slower switch, faster steady state
} API_AVAILABLE(ios(17.4));

typedef NS_ENUM(NSInteger, MLSpecializationStrategy) {
    MLSpecializationStrategyDefault        = 0,
    MLSpecializationStrategyFastPrediction = 1,  // latency at the cost of load time, memory, disk
} API_AVAILABLE(ios(18.0));
```

If the bucketed-fixed-shape contingency (`DEC-008`) activates, buckets are stable
shapes and `.infrequent` becomes the correct hint. With dynamic shapes, the
default `.frequent` is correct. **The hint choice follows the DEC-008 branch —
do not set it before V29 resolves.**

Compilation, ✅ VERIFIED (`MLModel+MLModelCompilation.h`): the synchronous
`+compileModelAtURL:error:` is **deprecated**; use
`+compileModelAtURL:completionHandler:`. `MLModelAsset` (`MLModelAsset.h`) offers
`+modelAssetWithURL:` and `+modelAssetWithSpecificationData:` if the model is
constructed from data rather than a bundle path.

**First-load cost is compilation, not inference.** A first-ever load compiles for
the target compute unit and takes seconds; subsequent loads hit the compiled-model
cache and are cheaper but not free. This is why spec `031` ties warm-up to a view
appearing rather than to a play action.

---

## 3. The ANE question — dynamic shapes

✅ **Shapes now VERIFIED** (2026-08-18) by compiling the FP16 bundle with
`xcrun coremlcompiler` and reading each `model.mil` signature. All four graphs
compile clean. Placement itself remains 🔴 — that is V29 and needs a device.

| Graph | Input signature | Flexible? |
|---|---|---|
| `TextEncoder` | `text_ids [1,128] int32`, `style_ttl [1,50,256]`, `text_mask [1,1,128]` | **Fully fixed** |
| `DurationPredictor` | `text_ids [1,128]`, `style_dp [1,8,16]`, `text_mask [1,1,128]` | **Fully fixed** |
| `VectorEstimator` | `noisy_latent [1,144,?]`, `text_emb [1,256,?]`, `latent_mask [1,1,?]`, `text_mask [1,1,?]`, `current_step [1]`, `total_step [1]` | **Dynamic**, `RangeDims` **17…512** on the last axis |
| `Vocoder` | `latent [1,144,?]` | **Dynamic**, `RangeDims` **4…512** on the last axis |

Three consequences, all of which improve the family's risk profile:

**1. The dynamic-shape risk is narrower than assumed.** Only `VectorEstimator`
and `Vocoder` vary, only on one axis, and over a **bounded** range declared in
the model. Bounded `RangeDims` are materially friendlier to the Neural Engine
than open-ended dynamic shapes. V29 still has to be measured, but it is no longer
the open-ended question the family was drafted around.

**2. `DEC-008` is cheaper than first recorded.** The earlier estimate — 3× a
243 MB graph, ~730 MB — assumed duplicating whole graphs. With one bounded axis,
the natural contingency is **enumerated shapes** (a small allowed set within
17…512) on the existing graph, not three separate exports. Treat ~730 MB as a
withdrawn worst case.

**3. ⚠️ A hard constraint nothing in the family anticipated: text is capped at
128 tokens per call.** `TextEncoder` and `DurationPredictor` are fixed at
`[1,128]` with an explicit `text_mask`, i.e. pad-and-mask. Any text longer than
128 tokens **must** be split by the app before synthesis. This is a ceiling on
chunk size, and spec `032`'s chunker must respect it — see that spec's amended
R1. Conveniently it pushes in the same direction the streaming design already
wanted, but it is a correctness requirement, not a tuning preference.

Per CONSTITUTION Rule 10, engine code still waits on V29's placement answer. The
shape facts above, however, are verified and may be built against.

---

## 4. Playback: `AVAudioEngine` + `AVAudioPlayerNode`

✅ **VERIFIED** — `AVFAudio.framework/Headers/AVAudioPlayerNode.h`, iOS 27.0 SDK
(27A5228h), 2026-08-18.

Synthesized `AVAudioPCMBuffer`s are scheduled directly onto a player node — no
intermediate files:

```objc
- (void)scheduleBuffer:(AVAudioPCMBuffer *)buffer
     completionHandler:(AVAudioNodeCompletionHandler __nullable)completionHandler;

- (void)scheduleBuffer:(AVAudioPCMBuffer *)buffer
                atTime:(AVAudioTime * __nullable)when
               options:(AVAudioPlayerNodeBufferOptions)options
completionCallbackType:(AVAudioPlayerNodeCompletionCallbackType)callbackType
     completionHandler:(AVAudioPlayerNodeCompletionHandler __nullable)completionHandler
     API_AVAILABLE(ios(11.0));
```

The callback type is the detail that matters for a speech queue — ✅ VERIFIED:

```objc
typedef NS_ENUM(NSInteger, AVAudioPlayerNodeCompletionCallbackType) {
    AVAudioPlayerNodeCompletionDataConsumed   = 0,
    AVAudioPlayerNodeCompletionDataRendered   = 1,
    AVAudioPlayerNodeCompletionDataPlayedBack = 2,
};
```

`DataConsumed` fires when the node has taken the buffer, **not** when the user
has heard it. Only `DataPlayedBack` accounts for the render pipeline and route
latency. Any "narration finished, re-arm the mic" logic must use
`DataPlayedBack`; using `DataConsumed` re-opens the mic while audio is still
sounding, which is exactly the class of ordering defect spec `028` R3 exists to
prevent.

**Two capabilities this unlocks that `AVSpeechSynthesizer` never had:**

1. **Known duration.** A rendered buffer's frame count over its sample rate is
   the exact duration. `VoicePlaybackService.swift`'s standing comment — *"an
   estimated scrubber would lie"* — stops applying on this path, so real
   `MPNowPlayingInfoCenter` duration and a scrubber become buildable (`06` §B5's
   full audio-app checklist).
2. **A real output envelope.** `NarrationGlow` currently feeds a synthetic sine
   while TTS speaks because playback amplitude is unavailable. Buffer samples are
   right there.

Neither is required by the family; both are recorded so they are not
re-discovered later.

---

## 5. Voice processing (AEC) for a full-duplex path

✅ **API VERIFIED** — `AVFAudio.framework/Headers/AVAudioIONode.h`, iOS 27.0 SDK
(27A5228h), 2026-08-18. 🔴 **Voice-quality impact UNVERIFIED — this is V30.**

```objc
- (BOOL)setVoiceProcessingEnabled:(BOOL)enabled error:(NSError **)outError
    API_AVAILABLE(ios(13.0));
@property (nonatomic, readonly, getter=isVoiceProcessingEnabled) BOOL voiceProcessingEnabled;
@property (nonatomic, getter=isVoiceProcessingBypassed)   BOOL voiceProcessingBypassed;
@property (nonatomic, getter=isVoiceProcessingAGCEnabled) BOOL voiceProcessingAGCEnabled;
@property (nonatomic, getter=isVoiceProcessingInputMuted) BOOL voiceProcessingInputMuted;
@property (nonatomic) AVAudioVoiceProcessingOtherAudioDuckingConfiguration
    voiceProcessingOtherAudioDuckingConfiguration API_AVAILABLE(ios(17.0));
```

Set on the engine's I/O node, this gives acoustic echo cancellation and automatic
gain control — the prerequisite for keeping the mic open while TTS plays.

**The cost is timbre.** Voice-processing I/O is tuned for telephony intelligibility,
not for a voice a user is meant to bond with; it audibly thins and nasalizes
output. This is not a bug to work around, it is the trade, and it is why the
voice roster must be auditioned **through this path** (V30 / `DEC-009`) rather
than through a clean playback path. A voice chosen on the hi-fi path and shipped
on the AEC path is a voice chosen wrong.

Two further facts, both ✅ VERIFIED in `AVAudioSession.h`:

- `AVAudioSessionCategoryPlayAndRecord` is the only category that admits both
  directions, and the header notes mode restrictions apply to it.
- `setPrefersNoInterruptionsFromSystemAlerts:` (ios 14.5) exists and is relevant
  to a live conversation turn.

🔴 **Sample rate is an open integration risk.** Supertonic emits 44.1 kHz;
voice-processing I/O commonly negotiates 48 kHz, and some routes 16 kHz. A
conversion stage (`AVAudioConverter`, exactly as `SpeechService.convertTo16kMono`
already does on the capture side) is therefore unavoidable on the conversation
path. Any spec text promising "no format conversions before the playback node"
is only true of the hi-fi read-back path.

---

## 6. Asset delivery — Background Assets ⚠️ SUPERSEDED

> **WITHDRAWN 2026-08-18 (`DEC-012`).** The model is **bundled in the app**; there
> is no download path at all. Sections 6 and 6a are retained because the API
> findings are accurate and were expensive to establish — if a future feature ever
> needs post-install delivery, start here rather than re-deriving it. **Nothing in
> §6 or §6a describes how this app ships today.** See spec `030` R2.

## 6. Asset delivery — Background Assets (self-hosted path)

✅ **VERIFIED, and better than assumed** — `BackgroundAssets.framework/Headers/`,
iOS 27.0 SDK (27A5228h), 2026-08-18. This materially simplifies spec `030`.

Background Assets supports **developer-hosted ("unmanaged") asset packs**, not
only Apple-hosted ones. The manifest is a JSON file the developer serves:

```objc
// BAAssetPackManifest.h — API_AVAILABLE(ios(26))
- (nullable instancetype)initWithContentsOfURL:(NSURL*)URL
                    applicationGroupIdentifier:(NSString*)applicationGroupIdentifier
                                         error:(NSError* _Nullable *)error
    NS_SWIFT_NAME(init(contentsOf:appGroupID:));
- (nullable instancetype)initFromData:(NSData*)data
           applicationGroupIdentifier:(NSString*)applicationGroupIdentifier
                                error:(NSError* _Nullable *)error
    NS_SWIFT_NAME(init(from:appGroupID:));
- (NSSet<BADownload*>*)allDownloads;
```

```objc
// BAAssetPack.h — API_AVAILABLE(ios(26))
@property (readonly, copy)   NSString* identifier NS_SWIFT_NAME(id);
@property (readonly, assign) NSInteger downloadSize;
@property (readonly, assign) NSInteger version;
@property (nullable, readonly, copy) NSData* userInfo;
```

```objc
// BAAssetPackManager.h — API_AVAILABLE(ios(26))
@property (class, readonly, strong) BAAssetPackManager* sharedManager;
- (void)ensureLocalAvailabilityOfAssetPack:(BAAssetPack*)assetPack ...;
- (BOOL)assetPackIsAvailableLocallyWithIdentifier:(NSString*)identifier   // ios(26.4)
- (void)checkForUpdatesWithCompletionHandler:...;
- (nullable NSData*)contentsAtPath:(NSString*)path
 searchingInAssetPackWithIdentifier:(nullable NSString*)assetPackIdentifier
                            options:(NSDataReadingOptions)options
                              error:(NSError* _Nullable *)error;
- (signed int)fileDescriptorForPath:(NSString*)path ...;
- (nullable NSURL*)URLForPath:(NSString*)path ...;
```

Notes that change how `030` should be written:

- **`BAAssetPack.version` is an integer the framework tracks**, and
  `checkForUpdatesWithCompletionHandler:` reports updated/removed identifiers.
  Asset versioning does not need to be invented; it needs to be *used*, with the
  spec's `ttsAssetVersion` mapping onto it.
- **All downloaded packs share one logical namespace** — a single root directory
  view across packs, addressed by relative path. Path collisions across packs are
  undefined unless an identifier is passed.
- **`URLForPath:` is the one that returns a file URL** — which is what
  `MLModel(contentsOf:)` / `MLModelAsset.modelAssetWithURL:` need. The header
  explicitly warns it is **less efficient** than `contentsAtPath:` /
  `fileDescriptorForPath:`, must not be used to get the namespace root, and
  **must not be called on the main thread**. Model loading therefore happens off
  the main actor by framework requirement, not merely by preference.
- `BAURLDownload` (ios 16.1, `initWithIdentifier:request:essential:fileSize:applicationGroupIdentifier:priority:`)
  plus `BADownloadManager.sharedManager` remains the lower-level path if
  per-file control is wanted instead of packs. `BADownload.isEssential`
  distinguishes install-blocking from post-install downloads.

### 6a. Apple will host them — added 2026-08-18

🟡 **LIKELY** — App Store Connect documentation, fetched 2026-08-18. Not an SDK
claim; Apple's own help pages, which are server-rendered and fetchable (the
`/documentation/` API pages are not — see the note in `00-INDEX.md` about
verifying APIs against the SDK instead).

The self-hosted path above is real, but it is not the only option and probably
not the right one. **Apple-hosted asset packs** are first-class for apps
targeting iOS 26+ — which this app is (`IPHONEOS_DEPLOYMENT_TARGET = 26.0`):

| Limit | Value |
|---|---|
| Asset pack total | **200 GB**, included in the Developer Program membership |
| Maximum asset packs per app | **200** |
| Scope | Shared across every platform the app offers |
| Notification | Email + banner at 80% of the total |

A ~250 MB model bundle is **0.125%** of that quota. Size does not constrain the
hosting decision at all.

Flow: package with Xcode's asset-pack command-line tool (or the Linux Managed
Background Assets tools) → upload to App Store Connect separately from the build
→ test through TestFlight → submit through App Review with the build. Versions
are tracked in App Store Connect, and from iOS 27 packs can be language-scoped.

**Why this is likely better for Memento than self-hosting:** it deletes the CDN,
TLS, and availability workstream; availability stops being a single developer's
operational risk; and it avoids standing up a Memento-operated endpoint in a
product whose first architectural non-negotiable is *no developer-operated
server*. It costs nothing against `REQ-TTS-001` either — delivery happens outside
synthesis, model-load and voice-selection time under both models.

**Cost of the switch:** the client API differs. Managed (Apple-hosted) packs are
not driven by `BAAssetPackManifest.init(contentsOf:appGroupID:)` over a manifest
we serve, so spec 030 R2's interface changes. `REQ-TTS-002`'s compiled-in SHA-256
manifest stays implementable and worth keeping under either model — the framework
managing delivery is not the same as the app verifying what it loads.

**Still open:** measured bundle size (spec 030 R7's 250 MB escalation threshold),
and whether App Review treats a model-weight pack differently from a content
pack. Neither blocks the hosting choice.

🔴 **Still open (V31):** whether App Review treats a self-hosted model-asset pack
of this size differently from self-hosted content assets, and what the operational
hosting requirements are (TLS, availability, CDN) **if self-hosting is chosen
anyway**. This is a policy and infrastructure question, not an API question — the
API is settled.

⚠️ Nothing here weakens the privacy posture: these are **our** assets from **our**
storage, fetched once, and none of it happens at synthesis time. The rule the
family enforces (`REQ-TTS-001`) is that the *synthesis path* makes no network
call — asset delivery is a separate, one-time, content-free transfer.

---

## 7. Licensing — the part that is not a technicality

🟡 **LIKELY — license texts read, not adjudicated by counsel.**

**GPL contamination in TTS text front-ends is the norm, not the exception.**
espeak-ng is GPL-3, and it sits inside the G2P/phonemizer path of Kokoro,
sherpa-onnx, and Piper. Shipping any of those in a closed-source app is a
license violation, and the contamination is easy to miss because it lives two
dependencies deep in a component nobody thinks of as "the model."

Supertonic 3 passes this test **because it is G2P-free** (§1) — there is no
phonemizer in the path to contaminate. That is the actual reason it is a
candidate, and it is why `018 R12` exists: any future engine must document its
full text-front-end dependency chain *before* evaluation, not after.

**The weights are OpenRAIL-M, not MIT-equivalent.** Two consequences:

1. **Attribution is a license condition**, not a courtesy — it ships in Settings →
   Acknowledgments (`DEC-010`).
2. **Use-based restrictions apply** (no impersonation or deception). Inapplicable
   to Memento reading a user their own journal. It becomes applicable the moment
   any feature lets a user generate audio in *someone else's* voice — that
   re-opens this review. On-device voice cloning is out of scope anyway: the
   style extractor was never released.

The integration surface is separately licensed from the weights. **Corrected
2026-08-18:** `soniqo/speech-swift` is **Apache-2.0**, not MIT, and
`supertone-inc/supertonic` is **MIT** — neither is archived (§1). Apache-2.0 is
permissive and carries a patent grant, so it clears the allowlist on the same
terms MIT would; the correction matters for attribution text, not admissibility.
Pin an exact commit regardless.

---

## 8. What this does not change

`06-speech-and-audio.md` remains correct on every point about the
`AVSpeechSynthesizer` path, which stays in the app permanently as the
degradation target (`REQ-TTS-003`):

- The complete-text constraint (§B1) still binds `AVSpeechSynthesizer`.
- Enhanced/Premium voice selection (§B2) still governs what the fallback picks.
- Personal Voice (§B3) is untouched and still gated on V6.
- Speakability (§B6) still applies — a neural voice reads markdown badly too.
  `SpeakabilityLinter` and `SpeechTextSanitizer` are unaffected; the spoken-form
  formatter (`035`) is a *third* transform composed with them, not a replacement.

---

## 9. Open items in this file

| Item | Question | Where |
|---|---|---|
| **V29** | Is the text-to-latent graph ANE-resident with dynamic latent length? | §2, §3 |
| **V30** | Do all four voices survive the voice-processing path? | §5 |
| **V31** | Self-hosted asset-pack policy, size, and hosting requirements | §6 |

All three are 🔴 and all three are device or policy questions — none resolves
from the SDK. See `11-verification-queue.md`.
