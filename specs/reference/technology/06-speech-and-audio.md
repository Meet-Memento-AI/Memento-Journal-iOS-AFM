# Speech and Audio — Capture and Voice Output

**Imports:** `import Speech`, `import AVFoundation`
**Role in Memento:** voice in (the primary capture path) and voice out (the long-term differentiator).

---

# PART A — CAPTURE

## A1. SpeechAnalyzer / SpeechTranscriber

✅ **VERIFIED** against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25 — `Speech.swiftmodule` interface. Both types exist in the `Speech` module, `@available(anyAppleOS 26, *)` (watchOS unavailable), present and stable in iOS 27. Exact declarations:

```swift
// SpeechAnalyzer is an ACTOR, not a class:
final public actor SpeechAnalyzer: Sendable {
    public convenience init(modules: [any SpeechModule],
                            options: SpeechAnalyzer.Options? = nil)
    public func start<InputSequence>(inputSequence: InputSequence) async throws
        where InputSequence: Sendable, InputSequence: AsyncSequence,
              InputSequence.Element == AnalyzerInput
    public func finalizeAndFinishThroughEndOfInput() async throws
    // also: analyzeSequence(_:), finalize(through:), finish(after:),
    //       cancelAndFinishNow(), setModules(_:),
    //       init(inputAudioFile:modules:...) for file-based analysis,
    //       static bestAvailableAudioFormat(compatibleWith:)
}

// SpeechTranscriber — options are Sets, and there are presets:
convenience init(locale: Locale, preset: SpeechTranscriber.Preset)
convenience init(locale: Locale,
    transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption>,
    reportingOptions: Set<SpeechTranscriber.ReportingOption>,       // .volatileResults, .alternativeTranscriptions, .fastResults
    attributeOptions: Set<SpeechTranscriber.ResultAttributeOption>) // .audioTimeRange, .transcriptionConfidence

// Presets: .transcription, .transcriptionWithAlternatives,
//          .timeIndexedTranscriptionWithAlternatives,
//          .progressiveTranscription, .timeIndexedProgressiveTranscription

// Result stream:
public var results: some Sendable & AsyncSequence<SpeechTranscriber.Result, any Error> { get }
public struct Result: SpeechModuleResult, Sendable {
    public let range: CMTimeRange
    public let resultsFinalizationTime: CMTime
    public var text: AttributedString { get }        // NOTE: AttributedString, not String
    public let alternatives: [AttributedString]
}
// isFinal comes from a SpeechModuleResult extension:
extension SpeechModuleResult { public var isFinal: Bool { get } }
```

The consumption sketch is therefore correct as written:

```swift
for try await result in transcriber.results {
    if result.isFinal {
        // finalized text — result.text is AttributedString
    } else {
        // volatile partial — render distinctly
    }
}
```

Confirmed architecture, exactly as documented: `SpeechAnalyzer` coordinates modules (`SpeechTranscriber`, plus `DictationTranscriber` and `SpeechDetector` exist as sibling modules); results arrive as an async sequence with volatile and finalized variants (`.volatileResults` reporting option + `isFinal`). Two deltas from the earlier sketch, neither architectural: option parameters are `Set`s (array literals still compile), and `result.text` is `AttributedString`. New in iOS 27: `SpeechAnalyzer.Options.ignoresResourceLimits` (`init(priority:modelRetention:ignoresResourceLimits:)`, `@available(anyAppleOS 27, *)`).

**Hard requirement: no cloud fallback.** The Gemini Audio API fallback from v1.3 is deleted. `SpeechAnalyzer` runs fully on-device, and that is the point.

## A2. Model assets

✅ **VERIFIED** against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25 — `Speech.swiftmodule` interface.

Locale models must be present before transcription works. Check and download via `AssetInventory` (all static, async):

```swift
// AssetInventory.Status: .unsupported, .downloading, .supported, .installed (Comparable)
public static func status(forModules modules: [any SpeechModule]) async -> AssetInventory.Status
public static func assetInstallationRequest(supporting modules: [any SpeechModule]) async throws -> AssetInstallationRequest?
// AssetInstallationRequest: NSObject, ProgressReporting, Sendable — has .progress for the download UI
public static func reserve(locale: Locale) async throws -> Bool     // plus release(reservedLocale:),
public static var maximumReservedLocales: Int { get }               // reservedLocales

// Locale support checks live on the transcriber itself:
SpeechTranscriber.isAvailable            // static Bool
SpeechTranscriber.supportedLocales       // static [Locale], async
SpeechTranscriber.installedLocales       // static [Locale], async
SpeechTranscriber.supportedLocale(equivalentTo:)  // async Locale?
```

**This is a first-run experience requirement, not an implementation detail.** A journaling app that silently fails to transcribe on first launch loses the user permanently. Show progress. Explain what's downloading. Let them type in the meantime.

## A3. Live partial transcription

Partial results MUST be shown during recording, and volatile results MUST render visually distinct from finalized ones (opacity, weight, or color). This is both a UX affordance and an honesty signal — the user sees the machine thinking rather than being presented with a confident wrong word.

## A4. AVAudioSession — the durability requirement

🟡 **LIKELY**

Recording MUST survive: app backgrounding, device lock, phone calls, Siri invocation, alarms, and route changes.

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetoothHFP, .defaultToSpeaker])
try session.setActive(true)

// Observe AVAudioSession.interruptionNotification
// Observe AVAudioSession.routeChangeNotification
```

⚠️ **DIFFERS from the original sketch** — verified against iOS 27.0 SDK (build 24A5390e), 2026-07-25: `AVAudioSessionCategoryOptionAllowBluetooth` is **deprecated with replacement** `AVAudioSessionCategoryOptionAllowBluetoothHFP` (Swift: `.allowBluetoothHFP`; same raw value `0x4`). Use the new name. Note also that A5's high-quality Bluetooth recording option is documented as *"currently compatible only with mode `AVAudioSessionModeDefault`"* — it cannot be combined with `mode: .spokenAudio`. If Memento adopts A5, the session must choose per route: `.spokenAudio` on built-in mic vs `.default` + `.bluetoothHighQualityRecording` on capable AirPods. Test both paths.

**Losing a two-minute confession to an incoming phone call is unrecoverable trust damage.** Handle `.began` by pausing and preserving buffered audio; handle `.ended` with `.shouldResume` by resuming. Write a test for it. Then test it on a real device by calling yourself.

`mode: .spokenAudio` is correct for voice journaling — it tunes processing for speech rather than music.

## A5. Audio routes and AirPods

✅ **API CONFIRMED** against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25 — `AVFAudio/AVAudioSessionTypes.h` and `AVAudioSessionRoute.h`:

```objc
AVAudioSessionCategoryOptionBluetoothHighQualityRecording
    API_AVAILABLE(ios(26.0)) = 1 << 19        // Swift: .bluetoothHighQualityRecording

// Query support/state per route (iOS 26+):
@interface AVAudioSessionPortExtensionBluetoothMicrophone : NSObject
@property (readonly) AVAudioSessionCapability *highQualityRecording;  // .isSupported / .isEnabled
@property (readonly) AVAudioSessionCapability *farFieldCapture;
@end
// Related: AVAudioSessionCategoryOptionFarFieldInput, ios(26.2)
```

Header semantics: enables *"full-bandwidth audio in both input & output directions, if the Bluetooth route supports it (e.g. certain AirPods models)"*; **only compatible with `AVAudioSessionModeDefault`** (see A4 DIFFERS note); when provided alone it degrades gracefully (ignored if unsupported), and may be combined with `.allowBluetoothHFP` as fallback; may increase input latency; Apple suggests `setPrefersNoInterruptionsFromSystemAlerts:` while recording.

🔴 Still open: the exact **hardware minimum** — the header says only "certain AirPods models"; determine the supported-device list empirically via `highQualityRecording.isSupported` or from marketing documentation, not the SDK.

Memento should prefer it when available and indicate the improved input in the UI. Voice journaling into AirPods while walking is a signature use case, and better input quality directly improves transcription accuracy, which improves everything downstream.

## A6. Text capture

Typing is a **first-class equal path**, not a fallback. Same `Entry` entity, same derived-field pipeline, `source == .text`. Do not build a lesser experience for it.

## A7. Multi-language

Transcription locale follows a user setting defaulting to device locale. The `Translation` framework (iOS 17.4+) 🟡 could later offer on-device translation of reflections into a second language for multilingual users. Specified but not scheduled for 2.0.

---

# PART B — VOICE OUTPUT

## B1. The constraint that shapes the architecture

✅ **VERIFIED, and load-bearing** — confirmed against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25:

> `AVSpeechSynthesizer` **cannot consume streaming text.** It requires the complete string before it begins generating audio.

SDK evidence: every `AVSpeechUtterance` initializer takes complete input — `initWithString:`, `initWithAttributedString:` (iOS 10), `initWithSSMLRepresentation:` (iOS 16). There is no streaming/token-input API, and `AVSpeechSynthesis.h` contains **zero** iOS 26 or iOS 27 additions. The only other synthesis surface in the entire SDK is `AVSpeechSynthesisProvider.h` (iOS 16) — the audio-unit *extension host* API for shipping custom voices, also request-based, not a streaming client API. An SDK-wide header sweep for speech synthesis found nothing else (see V18). The constraint stands.

This single fact determines Memento's interaction model:

| Surface | Streams? | Speakable? | Why |
|---|---|---|---|
| **Ask (chat)** | Yes — snapshot streaming | **No** | Can't synthesize a token stream |
| **Weekly / monthly reflection** | **No** — arrives complete | **Yes** | Full text exists before playback |

Do not try to defeat this by adding a third-party streaming TTS SDK (Picovoice Orca and similar exist). That would violate the single-dependency rule, add binary weight, and — depending on the vendor — puncture the privacy story. The constraint is telling you where the feature belongs. Listen to it.

A secondary benefit: a reflection that assembles itself word-by-word reads as a chatbot. Arriving complete reads as a considered observation. The technical constraint and the design intent agree.

## B2. System voices

✅ **VERIFIED** against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25 — `AVFAudio/AVSpeechSynthesis.h`: `+speechVoices`, `+voiceWithIdentifier:` (iOS 9), `quality` property, and `AVSpeechSynthesisVoiceQuality` = `.default` (1) / `.enhanced` / `.premium` (iOS 16). `AVSpeechUtteranceDefaultSpeechRate` present. All unchanged in iOS 27.

```swift
import AVFoundation

let synthesizer = AVSpeechSynthesizer()
let utterance = AVSpeechUtterance(string: reflection.body)
utterance.voice = AVSpeechSynthesisVoice(identifier: selectedVoiceIdentifier)
utterance.rate = AVSpeechUtteranceDefaultSpeechRate
synthesizer.speak(utterance)
```

Use **Enhanced or Premium** voices, not the default compact ones — the quality gap is large and the default voice will make the feature feel cheap. These require a user download; surface that in Settings with a clear prompt rather than failing silently to a robotic voice.

Enumerate with `AVSpeechSynthesisVoice.speechVoices()` and filter by quality.

## B3. Personal Voice — the differentiator

✅ **API VERIFIED** against iOS 27.0 SDK (build 24A5390e, Xcode 27 beta 4), 2026-07-25 — `AVFAudio/AVSpeechSynthesis.h`; all iOS 17 declarations present and unchanged in iOS 27 (App Review posture 🔴 still unverified — V6):

```objc
+ (void)requestPersonalVoiceAuthorizationWithCompletionHandler:
    (void(^)(AVSpeechSynthesisPersonalVoiceAuthorizationStatus status))handler;  // ios(17.0)
@property (class, readonly) AVSpeechSynthesisPersonalVoiceAuthorizationStatus
    personalVoiceAuthorizationStatus;                                            // ios(17.0)
// Status (Swift: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus):
//   .notDetermined / .denied / .unsupported / .authorized
// AVSpeechSynthesisVoiceTraits (Swift: AVSpeechSynthesisVoice.Traits):
//   AVSpeechSynthesisVoiceTraitIsPersonalVoice = 1 << 1
@property (readonly) AVSpeechSynthesisVoiceTraits voiceTraits;                   // ios(17.0)
```

```swift
// Swift usage as planned (async form also auto-generated from the handler API):
AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
    if status == .authorized {
        let personalVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.voiceTraits.contains(.isPersonalVoice) }
    }
}
```

The user trains it once in Settings by reading roughly 150 phrases (~15 minutes). Generation is **fully on-device (Z0)**.

**Why this is the feature:** Memento's weekly reflection, grounded in the user's own words, read back **in the user's own voice**. Slate cannot do this without abandoning its "never replies" doctrine. Cloud-AI journals cannot do it without shipping the user's voice to a server. It is emotionally heavier than anything else in the category and it is consistent with the privacy story.

**Product rules:**

1. **Delighter tier, never a default, never a gate.** Onboarding must not mention it.
2. **Surface it late** — after the user's third or fourth weekly reflection, at a moment of demonstrated engagement.
3. Default to Enhanced/Premium system voices for everyone else.
4. 🔴 **Verify App Review posture.** Personal Voice was introduced as an accessibility feature. Confirm that non-accessibility use in a journaling app is permitted before building the flow. This is a real risk, not a formality.

## B4. Caching

Render each `Reflection` to an audio file once and store the reference in `Reflection.audioAssetID`. Replay is then instant and does not re-synthesize. Invalidate if the voice selection changes.

## B5. Playback must behave like an audio app

The intended use is listening to a Sunday reflection on a walk. That means:

- **Background audio** capability in the app's background modes
- **Lock screen controls** via `MPRemoteCommandCenter`
- **`MPNowPlayingInfoCenter`** metadata — title, date, duration
- **AirPlay** support
- **CarPlay-safe** audio session configuration
- Correct interaction with other audio (ducking vs interrupting)

A "play" button that produces sound but doesn't appear on the lock screen is a half-built feature. Users will start it and lock their phone within five seconds.

## B6. Speakability — enforced, not aspirational

**REQ-VOX-006.** Every prompt producing user-facing prose forbids:

- markdown of any kind (`#`, `*`, `_`, backticks)
- bullet points and numbered lists
- headings
- emoji
- URLs
- parentheticals (they break spoken cadence)
- digits where words read better ("three" not "3")

And this is enforced in code, not trusted to the model:

```swift
struct SpeakabilityLinter {
    static func validate(_ text: String) throws {
        // reject: leading #, list markers (-, *, digit-dot),
        // inline emphasis markers, emoji ranges, http(s) URLs,
        // consecutive blank lines
    }
}
```

Violations **fail the build** when run against fixture-corpus generations. Retrofitting speakability after the prompts are tuned is a rewrite of every prompt, which is why it goes in from the first prompt.

## B7. Accessibility dividend

Because every reflection is audio-renderable, Memento is substantially usable without reading. This is a genuine accessibility strength that falls out of the TTS work at no additional cost. Lean into it in the App Store listing and make sure VoiceOver and the TTS playback don't fight each other.
