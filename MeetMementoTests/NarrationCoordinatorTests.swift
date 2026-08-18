import Combine
import XCTest
@testable import MeetMemento

// MARK: - Service mocks (spec 028 R8 seams)

/// Scripted stand-in for SpeechService: recording is a flag, transcripts are
/// whatever the test publishes.
@MainActor
private final class MockNarrationSpeech: NarrationSpeechListening {
    var audioLevel: Float = 0
    var bestAvailableTranscript = ""
    let partialSubject = CurrentValueSubject<String, Never>("")
    let recordingSubject = CurrentValueSubject<Bool, Never>(false)
    var partialTranscriptPublisher: AnyPublisher<String, Never> {
        partialSubject.eraseToAnyPublisher()
    }
    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        recordingSubject.eraseToAnyPublisher()
    }

    private(set) var owner: String?
    private(set) var startCount = 0
    private(set) var cancelCount = 0
    var startError: Error?

    func isOwner(_ ownerId: String) -> Bool { owner == ownerId }

    func startRecording(ownerId: String) async throws {
        if let startError { throw startError }
        startCount += 1
        owner = ownerId
        recordingSubject.send(true)
    }

    func stopRecording() async { recordingSubject.send(false) }

    func cancelRecording() async {
        cancelCount += 1
        owner = nil
        recordingSubject.send(false)
    }

    func clearTranscription() { owner = nil }
}

/// Scripted stand-in for VoicePlaybackService. `beginUtteranceSession`
/// publishes the message ID (as the real service does); the test drives queue
/// drain by publishing nil. `waitForSessionRelease` can be gated so tests can
/// prove the mic is not armed before the release completes.
@MainActor
private final class MockNarrationVoice: NarrationVoicePlayback {
    let speakingSubject = CurrentValueSubject<UUID?, Never>(nil)
    var speakingMessageIDPublisher: AnyPublisher<UUID?, Never> {
        speakingSubject.eraseToAnyPublisher()
    }

    private(set) var beganSessions: [UUID] = []
    private(set) var enqueued: [String] = []
    private(set) var finishCount = 0
    private(set) var stopCount = 0
    private(set) var releaseWaits = 0

    var releaseGateClosed = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func beginUtteranceSession(for messageID: UUID, title: String?) {
        beganSessions.append(messageID)
        speakingSubject.send(messageID)
    }

    func enqueue(sentence: String) { enqueued.append(sentence) }

    func finishEnqueueing() { finishCount += 1 }

    func stop() {
        stopCount += 1
        // Real service: clearSession() publishes nil synchronously.
        speakingSubject.send(nil)
    }

    private(set) var preactivateCount = 0
    private(set) var releasePreactivationCount = 0
    private(set) var barrierSetCount = 0

    func preactivateSession() { preactivateCount += 1 }

    func releasePreactivatedSession() { releasePreactivationCount += 1 }

    func setActivationBarrier(_ task: Task<Void, Never>?) { barrierSetCount += 1 }

    func ensureVoiceCatalogWarmed() async {}

    func warmSynthesizer() {}

    var queuedSpeechCount: Int { enqueued.count }

    func waitForSessionRelease() async {
        releaseWaits += 1
        if releaseGateClosed {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
    }

    func openReleaseGate() {
        releaseGateClosed = false
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

/// Narration mode's pure decision logic plus, via the spec 028 R8 seams, the
/// loop transitions themselves: loop-close re-arms the mic, the mic never arms
/// before the TTS session release completes, barge-in restarts listening, and
/// a dead listen recovers once then surfaces an error. Real mic ↔ TTS session
/// churn stays device-only (manual checklist).
@MainActor
final class NarrationCoordinatorTests: XCTestCase {

    // MARK: - shouldAutoSend decision table

    func test_emptyTranscript_neverFires() {
        XCTAssertFalse(NarrationCoordinator.shouldAutoSend(
            transcript: "", secondsSinceChange: 60, audioLevel: 0
        ))
        XCTAssertFalse(NarrationCoordinator.shouldAutoSend(
            transcript: "   \n", secondsSinceChange: 60, audioLevel: 0
        ))
    }

    func test_stableTranscriptAndSilence_fires() {
        XCTAssertTrue(NarrationCoordinator.shouldAutoSend(
            transcript: "I want to talk about my week",
            secondsSinceChange: NarrationCoordinator.autoSendPause,
            audioLevel: 0
        ))
    }

    func test_recentTranscriptChange_holds() {
        XCTAssertFalse(NarrationCoordinator.shouldAutoSend(
            transcript: "I want to talk about my week",
            secondsSinceChange: NarrationCoordinator.autoSendPause - 0.2,
            audioLevel: 0
        ))
    }

    func test_ambientNoise_blocksTheSend() {
        // The transcript went quiet but the room hasn't — don't cut in.
        XCTAssertTrue(
            NarrationCoordinator.autoSendMaxAudioLevel < 0.06,
            "gate must sit below normal speech levels (0.05–0.45)"
        )
        XCTAssertFalse(NarrationCoordinator.shouldAutoSend(
            transcript: "I want to talk about my week",
            secondsSinceChange: NarrationCoordinator.autoSendPause + 1,
            audioLevel: 0.2
        ))
    }

    // MARK: - Transcript scoping

    func test_transcriptStartIndex_snapshotsMessageCountAtStart() {
        let vm = ChatViewModel(chatService: MockChatService())
        vm.messages = [
            ChatMessage(content: "old one", isFromUser: true),
            ChatMessage(content: "old two", isFromUser: false),
        ]

        let coordinator = NarrationCoordinator()
        coordinator.start(chatViewModel: vm)
        // `start` snapshots synchronously; stop immediately so the async mic
        // spin-up sees an inactive session and never engages real audio.
        defer { coordinator.stop() }

        XCTAssertEqual(coordinator.transcriptStartIndex, 2,
                       "narration transcript must start after pre-existing history")
    }

    // MARK: - ChatViewModel.streamingAssistantMessageID lifecycle

    private func waitUntil(
        timeout: TimeInterval = 3.0,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    func test_streamingAssistantMessageID_setDuringSend_clearedOnFinal() async {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in
            // Keep the stream open long enough to observe the marker.
            try? await Task.sleep(nanoseconds: 200_000_000)
            return ChatResponse(
                reply: "A reply", heading1: nil, heading2: nil,
                citedEntryIds: nil, sources: [], sessionId: UUID().uuidString
            )
        }
        mock.fetchSessionsImpl = { [] }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")

        // Set synchronously with the placeholder append…
        let markedID = vm.streamingAssistantMessageID
        XCTAssertNotNil(markedID)
        XCTAssertEqual(vm.messages.last?.id, markedID,
                       "marker must point at the assistant placeholder")

        // …and cleared once the stream settles.
        await waitUntil { vm.streamingAssistantMessageID == nil }
        XCTAssertNil(vm.streamingAssistantMessageID)
        XCTAssertEqual(vm.messages.last?.content, "A reply")
    }

    func test_streamingAssistantMessageID_clearedOnError() async {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in
            throw NSError(domain: "t", code: 0)
        }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")
        XCTAssertNotNil(vm.streamingAssistantMessageID)

        await waitUntil { vm.streamingAssistantMessageID == nil }
        XCTAssertNil(vm.streamingAssistantMessageID,
                     "a failed send must settle the marker, or narration waits forever")
    }

    func test_streamingAssistantMessageID_clearedOnCancel() async {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return ChatResponse(
                reply: "too late", heading1: nil, heading2: nil,
                citedEntryIds: nil, sources: [], sessionId: UUID().uuidString
            )
        }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")
        XCTAssertNotNil(vm.streamingAssistantMessageID)

        vm.cancelActiveTasks()
        await waitUntil { vm.streamingAssistantMessageID == nil }
        XCTAssertNil(vm.streamingAssistantMessageID)
    }

    // MARK: - isListeningDead decision table (spec 028 R4)

    func test_isListeningDead_requiresNoActivityAndElapsedWindow() {
        let window = NarrationCoordinator.listeningLivenessTimeout
        XCTAssertTrue(NarrationCoordinator.isListeningDead(
            sawActivity: false, secondsListening: window
        ))
        XCTAssertFalse(NarrationCoordinator.isListeningDead(
            sawActivity: false, secondsListening: window - 0.1
        ), "the window must fully elapse before declaring death")
        XCTAssertFalse(NarrationCoordinator.isListeningDead(
            sawActivity: true, secondsListening: window * 10
        ), "any sign of life means the turn is a quiet user, not a dead session")
    }

    // MARK: - Loop transitions via the spec 028 R8 seams

    private func makeLoop(
        reply: String = "This is the assistant reply."
    ) -> (NarrationCoordinator, MockNarrationSpeech, MockNarrationVoice, ChatViewModel) {
        let mockChat = MockChatService()
        mockChat.sendMessageImpl = { _, _ in
            ChatResponse(reply: reply, heading1: nil, heading2: nil,
                         citedEntryIds: nil, sources: [], sessionId: UUID().uuidString)
        }
        mockChat.fetchSessionsImpl = { [] }
        let vm = ChatViewModel(chatService: mockChat)
        let speech = MockNarrationSpeech()
        let voice = MockNarrationVoice()
        let coordinator = NarrationCoordinator(speechService: speech, voiceService: voice)
        return (coordinator, speech, voice, vm)
    }

    /// Runs one full spoken turn: start → transcript → send → reply narrated.
    private func driveToSpeaking(
        _ coordinator: NarrationCoordinator,
        _ speech: MockNarrationSpeech,
        _ voice: MockNarrationVoice,
        _ vm: ChatViewModel
    ) async {
        coordinator.start(chatViewModel: vm)
        await waitUntil { speech.startCount == 1 }
        speech.partialSubject.send("Hello there")
        speech.bestAvailableTranscript = "Hello there"
        coordinator.micTapped() // send-now
        await waitUntil { coordinator.phase == .speaking }
    }

    func test_loopClose_reArmsTheMicForTheNextTurn() async {
        let (coordinator, speech, voice, vm) = makeLoop()
        defer { coordinator.stop() }

        await driveToSpeaking(coordinator, speech, voice, vm)
        XCTAssertEqual(voice.beganSessions.count, 1)
        XCTAssertFalse(voice.enqueued.isEmpty, "the reply must be narrated")

        // TTS queue drains → the loop must reopen the mic (the regression:
        // narration worked once, then hung on Listening… forever).
        voice.speakingSubject.send(nil)
        await waitUntil { speech.startCount == 2 }
        XCTAssertEqual(speech.startCount, 2, "loop close must re-arm the mic")
        XCTAssertEqual(coordinator.phase, .listening)
    }

    func test_micNeverArmsBeforeTheSessionReleaseCompletes() async {
        let (coordinator, speech, voice, vm) = makeLoop()
        defer { coordinator.stop() }

        // Gate the TTS session release: while a stale setActive(false) is
        // still in flight, arming the mic would hand it a session to kill.
        voice.releaseGateClosed = true
        coordinator.start(chatViewModel: vm)

        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(voice.releaseWaits, 1)
        XCTAssertEqual(speech.startCount, 0,
                       "startRecording must wait for waitForSessionRelease (spec 028 R3a)")

        voice.openReleaseGate()
        await waitUntil { speech.startCount == 1 }
        XCTAssertEqual(speech.startCount, 1)
    }

    func test_bargeInWhileSpeaking_restartsListening() async {
        let (coordinator, speech, voice, vm) = makeLoop()
        defer { coordinator.stop() }

        await driveToSpeaking(coordinator, speech, voice, vm)

        coordinator.micTapped() // barge-in
        XCTAssertEqual(voice.stopCount, 1, "barge-in must cut the narration")
        await waitUntil { speech.startCount == 2 }
        XCTAssertEqual(coordinator.phase, .listening,
                       "the cut session's nil publish must reopen the mic")
    }

    func test_deadListen_recoversOnce_thenSurfacesError() async {
        let (coordinator, speech, voice, vm) = makeLoop()
        defer { coordinator.stop() }
        _ = voice

        coordinator.livenessTimeout = 0.4
        coordinator.start(chatViewModel: vm)
        await waitUntil { speech.startCount == 1 }

        // No partials, audioLevel pinned at exactly 0: a dead session.
        // First death → silent re-arm.
        await waitUntil { speech.startCount == 2 }
        XCTAssertEqual(speech.cancelCount, 1, "the dead session must be cancelled first")
        XCTAssertNil(coordinator.errorKind, "first recovery is silent")

        // Second death in the same turn → surfaced error, no infinite re-arm.
        await waitUntil { coordinator.errorKind != nil }
        XCTAssertEqual(coordinator.errorKind, .recordingFailed)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(speech.startCount, 2, "one silent recovery per turn, no loop")
    }

    func test_sendTurn_preactivatesTTSWhileThinking() async {
        let (coordinator, speech, voice, vm) = makeLoop()
        defer { coordinator.stop() }

        await driveToSpeaking(coordinator, speech, voice, vm)
        // Pre-activation must have happened at sendTurn (mic already
        // released), so the TTS session cost hides behind model thinking.
        XCTAssertEqual(voice.preactivateCount, 1)
        XCTAssertEqual(voice.releasePreactivationCount, 0,
                       "a used pre-activation is consumed by the session, not released")
    }

    func test_failedSend_releasesPreactivatedSession() async {
        let (coordinator, speech, voice, vm) = makeLoop()
        defer { coordinator.stop() }
        // A send that throws drops the placeholder — narration returns to
        // listening and must release the unused pre-activation.
        let failing = MockChatService()
        failing.sendMessageImpl = { _, _ in throw NSError(domain: "t", code: 1) }
        let failingVM = ChatViewModel(chatService: failing)
        _ = vm

        coordinator.start(chatViewModel: failingVM)
        await waitUntil { speech.startCount == 1 }
        speech.partialSubject.send("Hello there")
        speech.bestAvailableTranscript = "Hello there"
        coordinator.micTapped()

        await waitUntil { speech.startCount == 2 }
        XCTAssertEqual(voice.preactivateCount, 1)
        XCTAssertGreaterThanOrEqual(voice.releasePreactivationCount, 1,
                                    "an unused pre-activation must be released before re-listening")
        XCTAssertEqual(coordinator.phase, .listening)
    }

    func test_emptyTranscriptTurn_loopsBackWithoutSending() async {
        let (coordinator, speech, voice, vm) = makeLoop()
        defer { coordinator.stop() }

        coordinator.start(chatViewModel: vm)
        await waitUntil { speech.startCount == 1 }

        // A partial appeared (so send-now is offered) but nothing salvageable
        // finalized — the turn must re-listen, not send an empty prompt.
        speech.partialSubject.send("uh")
        speech.bestAvailableTranscript = ""
        coordinator.micTapped()

        await waitUntil { speech.startCount == 2 }
        XCTAssertEqual(coordinator.phase, .listening)
        XCTAssertTrue(vm.messages.isEmpty, "an empty transcript must not be sent")
        XCTAssertTrue(voice.beganSessions.isEmpty)
    }
}
