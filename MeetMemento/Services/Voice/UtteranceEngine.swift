//
//  UtteranceEngine.swift
//  MeetMemento
//
//  The engine seam (spec 031 R2). One contract, two unlike implementations:
//  `SystemUtteranceEngine` (AVSpeechSynthesizer) and `NeuralUtteranceEngine`
//  (Supertonic + TTSPlayback). `VoicePlaybackService` talks only to this, and
//  therefore does not know which one is serving.
//
//  ⚠️ This deliberately sits *above* `SpeechSynthesizing`, and does not replace
//  it. Spec 031 R2 is explicit about why:
//
//    > The existing `SpeechSynthesizing` protocol is typed on
//    > `AVSpeechUtterance`/`AVSpeechBoundary` and is a **test** seam, not an
//    > engine abstraction. Do not widen it into a false abstraction over two
//    > unlike engines.
//
//  Conforming the neural path to `SpeechSynthesizing` would have been nearly
//  free, and wrong: `pauseSpeaking(at: .word)` has no meaning for a buffer
//  player that cannot see word boundaries, and `AVSpeechUtterance` carries a
//  dozen properties (`pitchMultiplier`, `voice`, `preUtteranceDelay`…) that are
//  inert for Supertonic. `SpeechSynthesizing` stays exactly as it is, doing the
//  job it does well — faking AVSpeechSynthesizer in unit tests — one layer down,
//  inside `SystemUtteranceEngine`.
//

import Foundation

/// Identity for one queued utterance.
///
/// Replaces `ObjectIdentifier(utterance)` as the session's bookkeeping key. The
/// reason that key had to be identity-based in the first place still holds and
/// is worth restating: when a new session starts while another is speaking, the
/// old session's completion callbacks arrive *after* the new session has
/// enqueued. A count would decrement the new session's bookkeeping and end it
/// early. An id that no longer appears in the active set is simply ignored.
struct UtteranceID: Hashable, Sendable {
    private let raw: UUID
    init() { raw = UUID() }
}

/// One thing to say. Text is already sanitized — `SpeechTextSanitizer` stays at
/// its single choke point inside `VoicePlaybackService.enqueue` and applies to
/// both engines (spec 031 R2).
struct UtteranceRequest: Sendable {
    let id: UtteranceID
    let text: String
    /// `AVSpeechUtteranceRate` scale, as persisted by `PreferencesService`.
    /// The neural engine converts via `SpeechRatePreset.neuralSpeed`; it is
    /// carried in this scale so the two engines stay interchangeable and the
    /// stored preference keeps exactly one meaning.
    let rate: Float
    /// A short breath after this utterance before the next is reported finished
    /// — heading → body, sentence → sentence.
    let postDelay: TimeInterval
}

@MainActor
protocol UtteranceEngineDelegate: AnyObject {
    /// First audio of this utterance is actually sounding.
    func utteranceDidStart(_ id: UtteranceID)
    /// This utterance is over — spoken to completion, or cancelled. The session
    /// state machine treats both identically (it only tracks "still outstanding"),
    /// so the two AVSpeech callbacks `didFinish` and `didCancel` collapse into
    /// this one event.
    ///
    /// **For the neural engine this MUST mean audio finished *playing*, not
    /// finished being handed to the player.** See `TTSPlayback`.
    func utteranceDidEnd(_ id: UtteranceID)
    func utteranceDidPause(_ id: UtteranceID)
    func utteranceDidResume(_ id: UtteranceID)
}

@MainActor
protocol UtteranceEngine: AnyObject {
    var engineDelegate: UtteranceEngineDelegate? { get set }

    /// Speaks, or queues behind whatever is already speaking. Order is the order
    /// of calls — an engine that synthesizes asynchronously must preserve it.
    func speak(_ request: UtteranceRequest)

    /// Drops everything, sounding and queued, immediately.
    func stopAll()

    /// Pauses/resumes at whatever granularity the engine supports.
    func pause()
    func resume()

    /// Spin-up so the first real utterance is not the one that pays load cost.
    /// Must be silent and must not report through the delegate.
    func warm()
}
