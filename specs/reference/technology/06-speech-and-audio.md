# Speech and Audio — Capture and Voice Output

**Imports:** `import Speech`, `import AVFoundation`
**Role in Memento:** voice in (the primary capture path) and voice out (the long-term differentiator).

---

# PART A — CAPTURE

## A1. SpeechAnalyzer / SpeechTranscriber

🟡 **LIKELY** (iOS 26 API, stable through iOS 27)

iOS 26 replaced `SFSpeechRecognizer` with a modular, offline-first, Swift-concurrency-native stack under the `Speech` module.

```swift
import Speech

let transcriber = SpeechTranscriber(
    locale: locale,
    transcriptionOptions: [...],
    reportingOptions: [.volatileResults],
    attributeOptions: [...]
)

let analyzer = SpeechAnalyzer(modules: [transcriber])

// Feed audio, consume results as an async sequence
for try await result in transcriber.results {
    if result.isFinal {
        // finalized text
    } else {
        // volatile partial — render distinctly
    }
}
```

🔴 Exact initializer parameters and result shape need SDK confirmation. The **architecture** is verified: `SpeechAnalyzer` is a coordinator taking modules; `SpeechTranscriber` is the transcription module; results arrive as an async sequence with volatile and finalized variants.

**Hard requirement: no cloud fallback.** The Gemini Audio API fallback from v1.3 is deleted. `SpeechAnalyzer` runs fully on-device, and that is the point.

## A2. Model assets

🟡 **LIKELY**

Locale models must be present before transcription works. Check and download via `AssetInventory`:

```swift
// Check availability for the locale, request installation if missing,
// surface download progress to the user
```

**This is a first-run experience requirement, not an implementation detail.** A journaling app that silently fails to transcribe on first launch loses the user permanently. Show progress. Explain what's downloading. Let them type in the meantime.

## A3. Live partial transcription

Partial results MUST be shown during recording, and volatile results MUST render visually distinct from finalized ones (opacity, weight, or color). This is both a UX affordance and an honesty signal — the user sees the machine thinking rather than being presented with a confident wrong word.

## A4. AVAudioSession — the durability requirement

🟡 **LIKELY**

Recording MUST survive: app backgrounding, device lock, phone calls, Siri invocation, alarms, and route changes.

```swift
let session = AVAudioSession.sharedInstance()
try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.allowBluetooth, .defaultToSpeaker])
try session.setActive(true)

// Observe AVAudioSession.interruptionNotification
// Observe AVAudioSession.routeChangeNotification
```

**Losing a two-minute confession to an incoming phone call is unrecoverable trust damage.** Handle `.began` by pausing and preserving buffered audio; handle `.ended` with `.shouldResume` by resuming. Write a test for it. Then test it on a real device by calling yourself.

`mode: .spokenAudio` is correct for voice journaling — it tunes processing for speech rather than music.

## A5. Audio routes and AirPods

🔴 **UNVERIFIED.** Secondary sources indicate recent AirPods models support a high-quality / studio-grade recording path exposed to apps. Confirm the API and the hardware minimum.

If it exists, Memento should prefer it when available and indicate the improved input in the UI. Voice journaling into AirPods while walking is a signature use case, and better input quality directly improves transcription accuracy, which improves everything downstream.

## A6. Text capture

Typing is a **first-class equal path**, not a fallback. Same `Entry` entity, same derived-field pipeline, `source == .text`. Do not build a lesser experience for it.

## A7. Multi-language

Transcription locale follows a user setting defaulting to device locale. The `Translation` framework (iOS 17.4+) 🟡 could later offer on-device translation of reflections into a second language for multilingual users. Specified but not scheduled for 2.0.

---

# PART B — VOICE OUTPUT

## B1. The constraint that shapes the architecture

🟡 **LIKELY, and load-bearing:**

> `AVSpeechSynthesizer` **cannot consume streaming text.** It requires the complete string before it begins generating audio.

This single fact determines Memento's interaction model:

| Surface | Streams? | Speakable? | Why |
|---|---|---|---|
| **Ask (chat)** | Yes — snapshot streaming | **No** | Can't synthesize a token stream |
| **Weekly / monthly reflection** | **No** — arrives complete | **Yes** | Full text exists before playback |

Do not try to defeat this by adding a third-party streaming TTS SDK (Picovoice Orca and similar exist). That would violate the single-dependency rule, add binary weight, and — depending on the vendor — puncture the privacy story. The constraint is telling you where the feature belongs. Listen to it.

A secondary benefit: a reflection that assembles itself word-by-word reads as a chatbot. Arriving complete reads as a considered observation. The technical constraint and the design intent agree.

## B2. System voices

🟡 **LIKELY**

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

🟡 **LIKELY** (iOS 17+ API; third-party access confirmed in principle, App Review posture 🔴 unverified)

```swift
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
