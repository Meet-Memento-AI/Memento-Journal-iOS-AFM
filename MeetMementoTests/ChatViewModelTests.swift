import XCTest
@testable import MeetMemento

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func waitForLoadingFalse(_ vm: ChatViewModel, timeout: TimeInterval = 3.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !vm.isLoading { return }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    func test_ChatViewModel_sendMessage_appendsUserAndAssistant() async throws {
        let sessionId = UUID()
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in
            ChatResponse(
                reply: "Assistant reply",
                heading1: nil,
                heading2: nil,
                citedEntryIds: nil,
                sources: [],
                sessionId: sessionId.uuidString
            )
        }
        mock.fetchSessionsImpl = { [] }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")

        await waitForLoadingFalse(vm)
        XCTAssertFalse(vm.showingError)
        XCTAssertEqual(vm.currentSessionId, sessionId)
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertTrue(vm.messages[0].isFromUser)
        XCTAssertFalse(vm.messages[1].isFromUser)
    }

    func test_ChatViewModel_sendMessage_mapsErrorToUserMessage() async throws {
        final class FNError: Error {
            let httpError = (404, "Not Found")
        }

        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in throw FNError() }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "x")

        await waitForLoadingFalse(vm)
        XCTAssertTrue(vm.showingError)
        XCTAssertEqual(vm.errorMessage, "Chat service is not set up yet. Please ensure Edge Functions are deployed.")
    }

    func test_ChatViewModel_sendMessage_genericError() async throws {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in
            throw NSError(domain: "t", code: 0, userInfo: [NSLocalizedDescriptionKey: "x"])
        }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "x")

        await waitForLoadingFalse(vm)
        XCTAssertTrue(vm.showingError)
        XCTAssertEqual(vm.errorMessage, "Unable to get a response. Please check your connection and try again.")
    }

    // MARK: - Streaming (spec 017 R6)

    func test_ChatViewModel_streamedSend_growsBubbleInPlace_thenFinalizes() async throws {
        let sessionId = UUID()
        let entryId = UUID()
        let mock = MockChatService()
        mock.fetchSessionsImpl = { [] }
        mock.streamEvents = [
            .partial(heading1: nil, heading2: nil, body: "You've"),
            .partial(heading1: nil, heading2: nil, body: "You've been writing about"),
            .completed(ChatResponse(
                reply: "You've been writing about work stress lately.",
                heading1: nil,
                heading2: nil,
                citedEntryIds: [entryId.uuidString],
                sources: [ChatSource(id: entryId.uuidString, createdAt: "2026-08-01T00:00:00Z", preview: "work was hard")],
                sessionId: sessionId.uuidString
            ))
        ]

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "what have I written about?")

        await waitForLoadingFalse(vm)
        XCTAssertFalse(vm.showingError)
        // Exactly one assistant bubble — partials mutate in place, never stack.
        XCTAssertEqual(vm.messages.count, 2)
        let assistant = vm.messages[1]
        XCTAssertFalse(assistant.isFromUser)
        XCTAssertEqual(assistant.content, "You've been writing about work stress lately.")
        // Streamed replies bypass the typewriter (real generation IS the animation).
        XCTAssertFalse(assistant.isNew)
        // Citations attach at completion.
        XCTAssertEqual(assistant.citations?.count, 1)
        XCTAssertEqual(assistant.citations?.first?.entryId, entryId)
        XCTAssertEqual(vm.currentSessionId, sessionId)
    }

    func test_ChatViewModel_guardrailRefusal_rendersDesignedBubble_notAlert() async throws {
        // Spec 017 R4: a guardrail refusal is a designed empty state — an
        // assistant bubble with the designed copy, no alert, no retry spinner,
        // no failure mark on the user's message.
        let mock = MockChatService()
        mock.streamError = IntelligenceError.guardrailRefusal

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "something raw and difficult")

        await waitForLoadingFalse(vm)
        XCTAssertFalse(vm.showingError, "guardrail refusal must never pop the error alert")
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertFalse(vm.messages[0].sendFailed, "the user's message is not a failure")
        XCTAssertEqual(vm.messages[1].content, "I don't have an observation for this one.")
    }

    func test_ChatViewModel_interruptedStream_removesPartialBubble() async throws {
        let mock = MockChatService()
        mock.streamEvents = [.partial(heading1: nil, heading2: nil, body: "You've been")]
        mock.streamError = IntelligenceError.generationFailed("model stopped")

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello there")

        await waitForLoadingFalse(vm)
        // The half-reply is gone; the user's message stays, marked for retry.
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertTrue(vm.messages[0].isFromUser)
        XCTAssertTrue(vm.messages[0].sendFailed)
        XCTAssertTrue(vm.showingError)
        XCTAssertEqual(vm.errorMessage, "I couldn't put a reflection together just now. Please try again.")
    }

    func test_ChatViewModel_unavailable_surfacesDesignedCopy() async throws {
        let mock = MockChatService()
        mock.streamError = IntelligenceError.unavailable(.deviceNotEligible)

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hi")

        await waitForLoadingFalse(vm)
        XCTAssertTrue(vm.showingError)
        XCTAssertEqual(
            vm.errorMessage,
            "On-device intelligence isn't available on this device, so reflections and chat are turned off here.",
            "availability copy must reach the user — never the connection guess"
        )
    }

    func test_ChatViewModel_generateChatSummary_returnsMockSummary() async throws {
        let mock = MockChatService()
        mock.summarizeChatImpl = { _, _ in
            ChatSummaryResponse(title: "T", content: "C")
        }
        let vm = ChatViewModel(chatService: mock)
        vm.messages = [ChatMessage(content: "u", isFromUser: true)]
        vm.currentSessionId = UUID()

        let result = try await vm.generateChatSummary()
        XCTAssertEqual(result.title, "T")
        XCTAssertEqual(result.content, "C")
    }
}
