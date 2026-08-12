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

    func test_ChatViewModel_sendMessage_genericError() async throws {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in
            throw NSError(domain: "t", code: 0, userInfo: [NSLocalizedDescriptionKey: "x"])
        }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "x")

        await waitForLoadingFalse(vm)
        XCTAssertTrue(vm.showingError)
        XCTAssertEqual(vm.errorMessage, "I couldn't put a reply together just now. Please try again.")
    }

    /// Spec 017 R4 / REQ-INT-011. A guardrail refusal on someone's own journal
    /// is a designed empty state, not a failure — grief, illness, conflict, and
    /// self-critical writing trip safety guardrails disproportionately, so this
    /// must never render as an error or imply judgment of what they wrote.
    ///
    /// Before this, the refusal reached the user as "check your connection" on
    /// an app with no network, with a retry spinner and a failure mark.
    func test_ChatViewModel_guardrailRefusal_rendersAsBubbleNotError() async throws {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in throw IntelligenceError.guardrailRefusal }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "I have been thinking about my mother's illness.")
        await waitForLoadingFalse(vm)

        XCTAssertFalse(vm.showingError, "a refusal must not raise an alert")
        XCTAssertEqual(vm.messages.count, 2, "the assistant bubble must survive, not be dropped")

        let assistant = try XCTUnwrap(vm.messages.last)
        XCTAssertFalse(assistant.isFromUser)
        XCTAssertEqual(assistant.content, "I don't have an observation for this one.")

        let userMessage = try XCTUnwrap(vm.messages.first)
        XCTAssertFalse(userMessage.sendFailed, "the person did nothing wrong — no failure mark")
    }

    /// Unavailability copy is written for the situation and is actionable
    /// ("Apple Intelligence is still getting ready"). It used to be swallowed
    /// into a generic connectivity message.
    func test_ChatViewModel_unavailable_surfacesItsOwnCopy() async throws {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in throw IntelligenceError.unavailable(.modelNotReady) }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")
        await waitForLoadingFalse(vm)

        XCTAssertTrue(vm.showingError)
        XCTAssertEqual(vm.errorMessage, "Apple Intelligence is still getting ready. Try again in a little while.")
    }

    /// The app has no network path, so no error message may advise the user to
    /// check their connection — it is advice they cannot act on, and it
    /// misdescribes every failure the on-device pipeline can actually produce.
    func test_ChatViewModel_noErrorMessageMentionsConnectivity() async throws {
        let errors: [Error] = [
            IntelligenceError.generationFailed("boom"),
            IntelligenceError.unavailable(.deviceNotEligible),
            IntelligenceError.unavailable(.modelNotReady),
            NSError(domain: "t", code: 0, userInfo: [NSLocalizedDescriptionKey: "x"]),
        ]

        for error in errors {
            let mock = MockChatService()
            mock.sendMessageImpl = { _, _ in throw error }
            let vm = ChatViewModel(chatService: mock)
            vm.sendMessage(prompt: "x")
            await waitForLoadingFalse(vm)

            let message = vm.errorMessage?.lowercased() ?? ""
            XCTAssertFalse(message.contains("connection"), "'\(message)' advises checking a connection")
            XCTAssertFalse(message.contains("offline"), "'\(message)' implies a network path")
            XCTAssertFalse(message.contains("sign in"), "'\(message)' references accounts, which no longer exist")
        }
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
