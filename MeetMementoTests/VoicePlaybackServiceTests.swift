import XCTest
import AVFoundation
@testable import MeetMemento

/// Drives VoicePlaybackService's state machine through the `UtteranceEngine`
/// seam — no real audio (simulator TTS is unreliable; CI is headless).
/// Completion is driven via `utteranceDidEnd(_:)` so tests stay synchronous
/// instead of racing a real engine.
///
/// The seam moved here from `SpeechSynthesizing` when the neural engine landed:
/// spec 031 R2 requires a narrow protocol *above* it rather than pretending
/// Supertonic is an AVSpeechSynthesizer. `SpeechSynthesizing` is still faked
/// below, one layer down, for the tests that cover AVSpeech translation itself.
@MainActor
final class VoicePlaybackServiceTests: XCTestCase {

    /// Records what the service asked to be spoken.
    private final class MockUtteranceEngine: UtteranceEngine {
        weak var engineDelegate: UtteranceEngineDelegate?
        var spokenUtterances: [UtteranceRequest] = []
        var stopCount = 0
        var pauseCount = 0
        var continueCount = 0
        var warmCount = 0

        func speak(_ request: UtteranceRequest) { spokenUtterances.append(request) }
        func stopAll() { stopCount += 1 }
        func pause() { pauseCount += 1 }
        func resume() { continueCount += 1 }
        func warm() { warmCount += 1 }
    }

    private final class MockSpeechSynthesizer: SpeechSynthesizing {
        var synthesizerDelegate: AVSpeechSynthesizerDelegate?
        var spokenUtterances: [AVSpeechUtterance] = []
        var stopCount = 0
        var pauseCount = 0
        var continueCount = 0

        func speak(_ utterance: AVSpeechUtterance) {
            spokenUtterances.append(utterance)
        }

        @discardableResult
        func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
            stopCount += 1
            return true
        }

        @discardableResult
        func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool {
            pauseCount += 1
            return true
        }

        @discardableResult
        func continueSpeaking() -> Bool {
            continueCount += 1
            return true
        }
    }

    private var mock: MockUtteranceEngine!
    private var service: VoicePlaybackService!
    private var isRecording = false

    override func setUp() {
        super.setUp()
        mock = MockUtteranceEngine()
        isRecording = false
        service = VoicePlaybackService(
            engineFactory: { [unowned self] _ in self.mock },
            managesAudioSession: false,
            isRecordingProvider: { [unowned self] in self.isRecording }
        )
    }

    private func end(_ request: UtteranceRequest) {
        service.utteranceDidEnd(request.id)
    }

    private func finishAll() {
        for request in mock.spokenUtterances { end(request) }
    }

    // MARK: - Toggle

    func test_toggleOnIdle_speaksSanitizedText() {
        let id = UUID()
        service.toggleSpeech(messageID: id, heading1: "**Heading**", heading2: nil,
                             body: "Body with **bold** text.")

        XCTAssertEqual(service.speakingMessageID, id)
        XCTAssertEqual(mock.spokenUtterances.count, 1)
        let spoken = mock.spokenUtterances[0].speechString
        XCTAssertFalse(spoken.contains("**"))
        XCTAssertTrue(spoken.contains("Heading."))
        XCTAssertTrue(spoken.contains("Body with bold text."))
    }

    func test_toggleSameID_pausesThenResumes() {
        // User decision: the in-app button never hard-stops — same-message
        // taps toggle pause/resume; the session stays alive throughout.
        let id = UUID()
        service.toggleSpeech(messageID: id, heading1: nil, heading2: nil, body: "Hello.")
        service.toggleSpeech(messageID: id, heading1: nil, heading2: nil, body: "Hello.")

        XCTAssertEqual(service.speakingMessageID, id)
        XCTAssertTrue(service.isPaused)
        XCTAssertEqual(mock.pauseCount, 1)
        XCTAssertEqual(mock.stopCount, 0)
        XCTAssertEqual(mock.spokenUtterances.count, 1)

        service.toggleSpeech(messageID: id, heading1: nil, heading2: nil, body: "Hello.")
        XCTAssertFalse(service.isPaused)
        XCTAssertEqual(mock.continueCount, 1)
        XCTAssertEqual(service.speakingMessageID, id)
    }

    func test_toggleOtherID_switchesSpeaker() {
        let first = UUID(), second = UUID()
        service.toggleSpeech(messageID: first, heading1: nil, heading2: nil, body: "One.")
        service.toggleSpeech(messageID: second, heading1: nil, heading2: nil, body: "Two.")

        XCTAssertEqual(service.speakingMessageID, second)
        XCTAssertEqual(mock.stopCount, 1)
        XCTAssertEqual(mock.spokenUtterances.count, 2)
    }

    func test_toggleWhileRecording_noOps() {
        isRecording = true
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")

        XCTAssertNil(service.speakingMessageID)
        XCTAssertTrue(mock.spokenUtterances.isEmpty)
    }

    func test_emptyAfterSanitizing_noOps() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "🎉 ✨")

        XCTAssertNil(service.speakingMessageID)
        XCTAssertTrue(mock.spokenUtterances.isEmpty)
    }

    // MARK: - Queue drain

    func test_lastUtteranceFinishing_endsSession() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Done.")
        finishAll()

        XCTAssertNil(service.speakingMessageID)
        XCTAssertFalse(service.isSpeaking)
    }

    func test_finishWithUtterancesPending_keepsSession() {
        let id = UUID()
        service.beginUtteranceSession(for: id)
        service.enqueue(sentence: "First.")
        service.enqueue(sentence: "Second.")
        service.finishEnqueueing()

        end(mock.spokenUtterances[0])
        XCTAssertEqual(service.speakingMessageID, id, "session must survive a mid-queue finish")

        end(mock.spokenUtterances[1])
        XCTAssertNil(service.speakingMessageID)
    }

    func test_streamingSession_queueDrainBeforeFinishEnqueueing_keepsSession() {
        // The future chunker's shape: the synthesizer outruns the stream.
        let id = UUID()
        service.beginUtteranceSession(for: id)
        service.enqueue(sentence: "First sentence.")
        end(mock.spokenUtterances[0])

        XCTAssertEqual(service.speakingMessageID, id,
                       "drained queue without finishEnqueueing must not end the session")

        service.enqueue(sentence: "Late-arriving sentence.")
        service.finishEnqueueing()
        end(mock.spokenUtterances[1])
        XCTAssertNil(service.speakingMessageID)
    }

    // MARK: - Stale callbacks

    func test_oldSessionsCancelCallback_cannotEndNewSession() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Old.")
        let oldUtterance = mock.spokenUtterances[0]

        let newID = UUID()
        service.toggleSpeech(messageID: newID, heading1: nil, heading2: nil, body: "New.")

        // didCancel for the old session's utterance arrives after the new
        // session already enqueued — it must not touch the new bookkeeping.
        end(oldUtterance)
        XCTAssertEqual(service.speakingMessageID, newID)

        end(mock.spokenUtterances[1])
        XCTAssertNil(service.speakingMessageID)
    }

    func test_callbackAfterStop_isIgnored() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        let utterance = mock.spokenUtterances[0]
        service.stop()

        end(utterance)
        XCTAssertNil(service.speakingMessageID)
        XCTAssertFalse(service.isSpeaking)
    }

    // MARK: - Targeted stop

    func test_stopIfSpeaking_nonMatchingID_noOps() {
        let id = UUID()
        service.toggleSpeech(messageID: id, heading1: nil, heading2: nil, body: "Hi.")
        service.stopIfSpeaking(messageID: UUID())

        XCTAssertEqual(service.speakingMessageID, id)
        XCTAssertEqual(mock.stopCount, 0)
    }

    func test_stopIfSpeaking_matchingID_stops() {
        let id = UUID()
        service.toggleSpeech(messageID: id, heading1: nil, heading2: nil, body: "Hi.")
        service.stopIfSpeaking(messageID: id)

        XCTAssertNil(service.speakingMessageID)
        XCTAssertEqual(mock.stopCount, 1)
    }

    // MARK: - Pause / resume

    func test_pauseWhenIdle_noOps() {
        service.pauseSpeaking()
        XCTAssertFalse(service.isPaused)
        XCTAssertEqual(mock.pauseCount, 0)
    }

    func test_resumeWhenNotPaused_noOps() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        service.continueSpeaking()
        XCTAssertEqual(mock.continueCount, 0)
    }

    func test_stopWhilePaused_clearsSession() {
        let id = UUID()
        service.toggleSpeech(messageID: id, heading1: nil, heading2: nil, body: "Hi.")
        service.pauseSpeaking()
        service.stop()

        XCTAssertNil(service.speakingMessageID)
        XCTAssertFalse(service.isPaused)
    }

    func test_newSessionWhilePaused_startsUnpaused() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "One.")
        service.pauseSpeaking()
        let second = UUID()
        service.toggleSpeech(messageID: second, heading1: nil, heading2: nil, body: "Two.")

        XCTAssertEqual(service.speakingMessageID, second)
        XCTAssertFalse(service.isPaused)
    }

    // MARK: - Interruptions

    func test_interruptionBegan_pauses() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        service.interruptionBegan()

        XCTAssertTrue(service.isPaused)
        XCTAssertEqual(mock.pauseCount, 1)
        XCTAssertNotNil(service.speakingMessageID, "interruption must pause, not stop")
    }

    func test_interruptionEnded_withShouldResume_resumes() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        service.interruptionBegan()
        service.interruptionEnded(shouldResume: true)

        XCTAssertFalse(service.isPaused)
        XCTAssertEqual(mock.continueCount, 1)
    }

    func test_interruptionEnded_withoutShouldResume_staysPaused() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        service.interruptionBegan()
        service.interruptionEnded(shouldResume: false)

        XCTAssertTrue(service.isPaused)
        XCTAssertEqual(mock.continueCount, 0)
    }

    // MARK: - Rate preference

    /// The preference is read per utterance, not cached at session start.
    ///
    /// Expectations carry `readBackRateMultiplier` because `deliveryMode`
    /// defaults to `.readBack` (spec 035): tap-to-read is deliberately 0.95x.
    /// Asserting the bare preference here is what made this test drift once the
    /// multiplier landed, so it is expressed against the constant instead of a
    /// literal — if the pacing changes, this test should not.
    func test_enqueueAppliesInjectedRate() {
        var rate: Float = 0.45
        let localMock = MockUtteranceEngine()
        let localService = VoicePlaybackService(
            engineFactory: { _ in localMock }, managesAudioSession: false,
            rateProvider: { rate }
        )
        localService.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "One.")
        rate = 0.58
        localService.beginUtteranceSession(for: UUID())
        localService.enqueue(sentence: "Two.")

        let readBack = SpokenFormFormatter.readBackRateMultiplier
        XCTAssertEqual(localMock.spokenUtterances[0].rate, 0.45 * readBack, accuracy: 1e-5)
        XCTAssertEqual(localMock.spokenUtterances[1].rate, 0.58 * readBack, accuracy: 1e-5,
                       "rate must be read per utterance")
    }

    /// The clamp moved with the utterance construction it belongs to: the
    /// service now carries the raw preference and `SystemUtteranceEngine`
    /// applies AVSpeech's own bounds. Tested where it lives.
    func test_systemEngineClampsOutOfRangeRate() {
        let synth = MockSpeechSynthesizer()
        let engine = SystemUtteranceEngine(synthesizer: synth)
        engine.speak(UtteranceRequest(id: UtteranceID(), text: "Hi.",
                                      rate: 9.9, postDelay: 0.1))
        XCTAssertLessThanOrEqual(synth.spokenUtterances[0].rate,
                                 AVSpeechUtteranceMaximumSpeechRate)
    }

    /// The service applies the delivery-mode multiplier and nothing else —
    /// clamping is not its job, and doing it in both places would hide a
    /// disagreement.
    func test_serviceForwardsRateWithoutClamping() {
        let localMock = MockUtteranceEngine()
        let localService = VoicePlaybackService(
            engineFactory: { _ in localMock }, managesAudioSession: false,
            rateProvider: { 0.45 }
        )
        localService.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        XCTAssertEqual(localMock.spokenUtterances[0].rate,
                       0.45 * SpokenFormFormatter.readBackRateMultiplier, accuracy: 1e-5)
    }

    /// The pacing split itself (spec 035). This is the assertion whose absence
    /// let the two tests above drift: nothing pinned which multiplier a mode
    /// gets, so changing one silently broke tests that were about something
    /// else entirely.
    ///
    /// The two modes are reached through different entry points on purpose.
    /// `toggleSpeech` *is* tap-to-read and sets `.readBack` itself, so the
    /// conversation case has to go through the narration path
    /// (`beginUtteranceSession` + `enqueue`) the way `NarrationCoordinator`
    /// does — setting `deliveryMode` before calling `toggleSpeech` would be
    /// silently overwritten.
    func test_deliveryModeSelectsRateMultiplier() {
        let readBackMock = MockUtteranceEngine()
        let readBackService = VoicePlaybackService(
            engineFactory: { _ in readBackMock }, managesAudioSession: false,
            rateProvider: { 0.5 }
        )
        readBackService.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        XCTAssertEqual(readBackMock.spokenUtterances[0].rate,
                       0.5 * SpokenFormFormatter.readBackRateMultiplier, accuracy: 1e-5,
                       "tap-to-read must use the read-back multiplier")

        let conversationMock = MockUtteranceEngine()
        let conversationService = VoicePlaybackService(
            engineFactory: { _ in conversationMock }, managesAudioSession: false,
            rateProvider: { 0.5 }
        )
        conversationService.deliveryMode = .conversation
        conversationService.beginUtteranceSession(for: UUID())
        conversationService.enqueue(sentence: "Hi.")
        XCTAssertEqual(conversationMock.spokenUtterances[0].rate,
                       0.5 * SpokenFormFormatter.conversationRateMultiplier, accuracy: 1e-5,
                       "narration must use the conversation multiplier")
    }

    // MARK: - shouldReleaseAudioSession decision table (spec 028 R3b)

    func test_shouldReleaseAudioSession_allClear_releases() {
        XCTAssertTrue(VoicePlaybackService.shouldReleaseAudioSession(
            scheduledGeneration: 7, currentGeneration: 7,
            isRecording: false, speakingMessageID: nil
        ))
    }

    func test_shouldReleaseAudioSession_staleGeneration_skips() {
        // A newer TTS session owns the audio session; the old teardown must
        // not deactivate it (barge-in → immediate next reply).
        XCTAssertFalse(VoicePlaybackService.shouldReleaseAudioSession(
            scheduledGeneration: 7, currentGeneration: 8,
            isRecording: false, speakingMessageID: nil
        ))
    }

    func test_shouldReleaseAudioSession_liveRecording_skips() {
        // STT owns the shared session now (narration's next turn, or inline
        // dictation after the yield sink) — deactivating would dead-mic it.
        XCTAssertFalse(VoicePlaybackService.shouldReleaseAudioSession(
            scheduledGeneration: 7, currentGeneration: 7,
            isRecording: true, speakingMessageID: nil
        ))
    }

    func test_shouldReleaseAudioSession_newSpeakingSession_skips() {
        XCTAssertFalse(VoicePlaybackService.shouldReleaseAudioSession(
            scheduledGeneration: 7, currentGeneration: 7,
            isRecording: false, speakingMessageID: UUID()
        ))
    }
}

/// Test-local sugar: the old assertions read `.speechString` because the seam
/// spoke `AVSpeechUtterance`. The text is the same text.
extension UtteranceRequest {
    var speechString: String { text }
}
