import XCTest
import AVFoundation
@testable import MeetMemento

/// Drives VoicePlaybackService's state machine through the SpeechSynthesizing
/// seam — no real audio (simulator TTS is unreliable; CI is headless). Delegate
/// transitions are exercised via the internal `utteranceEnded(_:)` hook so
/// tests stay synchronous instead of racing the delegate's main-actor hop.
@MainActor
final class VoicePlaybackServiceTests: XCTestCase {

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

    private var mock: MockSpeechSynthesizer!
    private var service: VoicePlaybackService!
    private var isRecording = false

    override func setUp() {
        super.setUp()
        mock = MockSpeechSynthesizer()
        isRecording = false
        service = VoicePlaybackService(
            synthesizer: mock,
            managesAudioSession: false,
            isRecordingProvider: { [unowned self] in self.isRecording }
        )
    }

    private func finishAll() {
        for utterance in mock.spokenUtterances {
            service.utteranceEnded(utterance)
        }
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

        service.utteranceEnded(mock.spokenUtterances[0])
        XCTAssertEqual(service.speakingMessageID, id, "session must survive a mid-queue finish")

        service.utteranceEnded(mock.spokenUtterances[1])
        XCTAssertNil(service.speakingMessageID)
    }

    func test_streamingSession_queueDrainBeforeFinishEnqueueing_keepsSession() {
        // The future chunker's shape: the synthesizer outruns the stream.
        let id = UUID()
        service.beginUtteranceSession(for: id)
        service.enqueue(sentence: "First sentence.")
        service.utteranceEnded(mock.spokenUtterances[0])

        XCTAssertEqual(service.speakingMessageID, id,
                       "drained queue without finishEnqueueing must not end the session")

        service.enqueue(sentence: "Late-arriving sentence.")
        service.finishEnqueueing()
        service.utteranceEnded(mock.spokenUtterances[1])
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
        service.utteranceEnded(oldUtterance)
        XCTAssertEqual(service.speakingMessageID, newID)

        service.utteranceEnded(mock.spokenUtterances[1])
        XCTAssertNil(service.speakingMessageID)
    }

    func test_callbackAfterStop_isIgnored() {
        service.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        let utterance = mock.spokenUtterances[0]
        service.stop()

        service.utteranceEnded(utterance)
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

    func test_enqueueAppliesInjectedRate() {
        var rate: Float = 0.45
        let localMock = MockSpeechSynthesizer()
        let localService = VoicePlaybackService(
            synthesizer: localMock, managesAudioSession: false,
            rateProvider: { rate }
        )
        localService.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "One.")
        rate = 0.58
        localService.beginUtteranceSession(for: UUID())
        localService.enqueue(sentence: "Two.")

        XCTAssertEqual(localMock.spokenUtterances[0].rate, 0.45)
        XCTAssertEqual(localMock.spokenUtterances[1].rate, 0.58, "rate must be read per utterance")
    }

    func test_enqueueClampsOutOfRangeRate() {
        let localMock = MockSpeechSynthesizer()
        let localService = VoicePlaybackService(
            synthesizer: localMock, managesAudioSession: false,
            rateProvider: { 9.9 }
        )
        localService.toggleSpeech(messageID: UUID(), heading1: nil, heading2: nil, body: "Hi.")
        XCTAssertLessThanOrEqual(localMock.spokenUtterances[0].rate,
                                 AVSpeechUtteranceMaximumSpeechRate)
    }
}
