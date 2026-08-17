import XCTest
@testable import MeetMemento

/// Narration mode's pure decision logic. The full loop (mic ↔ TTS session
/// churn) is device-only behavior exercised by the manual checklist; what unit
/// tests can pin down is the auto-send decision table and the send-marker
/// lifecycle the coordinator observes on ChatViewModel.
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
}
