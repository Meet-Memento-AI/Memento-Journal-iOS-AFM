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

    // MARK: - Transcript generation

    /// The regression that made a new chat's first reply unreadable.
    ///
    /// `.final` mints a session id mid-conversation on the first send of a new
    /// chat. The view used to watch `currentSessionId`, so that mint read as
    /// "the user opened a different conversation": the pin was dropped and the
    /// transcript scrolled to the bottom the instant the reply completed,
    /// leaving the reader on the last line of an answer they had just watched
    /// arrive. Nothing about the transcript was replaced, so nothing may bump.
    func test_transcriptGeneration_doesNotBumpWhenTheFirstReplyMintsASessionId() async throws {
        let sessionId = UUID()
        let mock = MockChatService()
        mock.fetchSessionsImpl = { [] }
        mock.sendMessageImpl = { _, _ in
            ChatResponse(reply: "a long agentic answer", heading1: nil, heading2: nil,
                         citedEntryIds: nil, sources: [], sessionId: sessionId.uuidString)
        }

        let vm = ChatViewModel(chatService: mock)
        let before = vm.transcriptGeneration
        XCTAssertNil(vm.currentSessionId)

        vm.sendMessage(prompt: "hello")
        await waitForLoadingFalse(vm)

        XCTAssertEqual(vm.currentSessionId, sessionId, "the id must still be adopted")
        XCTAssertEqual(vm.transcriptGeneration, before,
                       "naming the conversation already on screen is not a new transcript")
    }

    func test_transcriptGeneration_bumpsOnStartNewChat() {
        let vm = ChatViewModel(chatService: stalledService())
        let before = vm.transcriptGeneration
        vm.startNewChat()
        XCTAssertEqual(vm.transcriptGeneration, before + 1)
    }

    /// Both branches of `loadSession` replace the transcript, so the bump has to
    /// sit above the cached early-return.
    func test_transcriptGeneration_bumpsOnLoadSession_cachedAndFetched() async {
        let mock = MockChatService()
        mock.fetchSessionsImpl = { [] }
        mock.loadSessionMessagesImpl = { _ in [] }
        let vm = ChatViewModel(chatService: mock)
        let session = ChatSession(title: "a", createdAt: Date())

        let before = vm.transcriptGeneration
        await vm.loadSession(session)
        XCTAssertEqual(vm.transcriptGeneration, before + 1, "fetched path")

        await vm.loadSession(session)   // now cached
        XCTAssertEqual(vm.transcriptGeneration, before + 2, "cached path must bump too")
    }

    /// `cancelActiveTasks` runs on every swipe back to Journal and at the top of
    /// every `loadSession`. It stops work; it does not replace the transcript.
    /// If it bumped, leaving the page mid-reply would scroll the thread to the
    /// bottom and drop the pin — and `loadSession` would bump twice.
    func test_transcriptGeneration_doesNotBumpOnCancelActiveTasks() {
        let vm = ChatViewModel(chatService: stalledService())
        vm.sendMessage(prompt: "hello")
        let before = vm.transcriptGeneration
        vm.cancelActiveTasks()
        XCTAssertEqual(vm.transcriptGeneration, before)
    }

    /// Retry re-sends inside the conversation already on screen.
    func test_transcriptGeneration_doesNotBumpOnRetry() async throws {
        let mock = MockChatService()
        mock.fetchSessionsImpl = { [] }
        mock.sendMessageImpl = { _, _ in throw URLError(.notConnectedToInternet) }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")
        await waitForLoadingFalse(vm)
        let before = vm.transcriptGeneration

        let failed = try XCTUnwrap(vm.messages.first(where: { $0.isFromUser }))
        vm.retryMessage(failed)
        await waitForLoadingFalse(vm)

        XCTAssertEqual(vm.transcriptGeneration, before)
        vm.cancelActiveTasks()
    }

    // MARK: - Send ticket

    /// A quiet service, so the ticket can be inspected before the reply lands.
    private func stalledService() -> MockChatService {
        let mock = MockChatService()
        mock.fetchSessionsImpl = { [] }
        mock.sendMessageImpl = { _, _ in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return ChatResponse(reply: "later", heading1: nil, heading2: nil,
                                citedEntryIds: nil, sources: [], sessionId: UUID().uuidString)
        }
        return mock
    }

    /// The ticket must land after BOTH appends. `messages.count` fires twice per
    /// send and its second firing points at the empty assistant placeholder, so
    /// a view driving off it would choreograph around the wrong message.
    func test_ChatViewModel_lastSend_publishesAfterBothAppends() async throws {
        let vm = ChatViewModel(chatService: stalledService())
        XCTAssertNil(vm.lastSend)

        vm.sendMessage(prompt: "hello")

        let ticket = try XCTUnwrap(vm.lastSend)
        XCTAssertEqual(vm.messages.count, 2, "user message and assistant placeholder both present")
        XCTAssertEqual(ticket.userMessageID, vm.messages[0].id, "ticket names the USER message")
        XCTAssertTrue(vm.messages[0].isFromUser)

        vm.cancelActiveTasks()
    }

    func test_ChatViewModel_lastSend_carriesTheComposerOrigin() async throws {
        let vm = ChatViewModel(chatService: stalledService())
        vm.sendMessage(prompt: "hello")

        XCTAssertEqual(vm.lastSend?.origin, .composer)
        vm.cancelActiveTasks()
    }

    func test_ChatViewModel_lastSend_carriesTheNarrationOrigin() async throws {
        let vm = ChatViewModel(chatService: stalledService())
        vm.sendMessage(prompt: "hello", origin: .narration)

        XCTAssertEqual(vm.lastSend?.origin, .narration,
                       "narration has no composer on screen, so it must not fly a bubble")
        vm.cancelActiveTasks()
    }

    func test_ChatViewModel_lastSend_carriesTheRetryOrigin() async throws {
        let mock = MockChatService()
        mock.fetchSessionsImpl = { [] }
        mock.sendMessageImpl = { _, _ in throw URLError(.notConnectedToInternet) }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")
        await waitForLoadingFalse(vm)

        let failed = try XCTUnwrap(vm.messages.first(where: { $0.isFromUser }))
        XCTAssertTrue(failed.sendFailed)

        vm.retryMessage(failed)
        XCTAssertEqual(vm.lastSend?.origin, .retry)
        XCTAssertEqual(vm.lastSend?.userMessageID, failed.id, "retry reuses the existing bubble")

        vm.cancelActiveTasks()
    }

    /// Without a sequence number two retries of the same message would compare
    /// equal, `onChange` would not fire, and the second retry would not
    /// re-establish the pin.
    func test_ChatViewModel_lastSend_seqDistinguishesRepeatedRetries() async throws {
        let mock = MockChatService()
        mock.fetchSessionsImpl = { [] }
        mock.sendMessageImpl = { _, _ in throw URLError(.notConnectedToInternet) }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "hello")
        await waitForLoadingFalse(vm)

        let failed = try XCTUnwrap(vm.messages.first(where: { $0.isFromUser }))
        vm.retryMessage(failed)
        let first = try XCTUnwrap(vm.lastSend)
        await waitForLoadingFalse(vm)

        let retried = try XCTUnwrap(vm.messages.first(where: { $0.isFromUser }))
        vm.retryMessage(retried)
        let second = try XCTUnwrap(vm.lastSend)

        XCTAssertEqual(first.userMessageID, second.userMessageID)
        XCTAssertNotEqual(first, second, "same id, different send — must not compare equal")
        XCTAssertGreaterThan(second.seq, first.seq)

        vm.cancelActiveTasks()
    }

    func test_ChatViewModel_lastSend_clearedByCancelAndNewChat() async throws {
        let vm = ChatViewModel(chatService: stalledService())

        vm.sendMessage(prompt: "hello")
        XCTAssertNotNil(vm.lastSend)
        vm.cancelActiveTasks()
        XCTAssertNil(vm.lastSend, "a cancelled send must not re-trigger the choreography")

        vm.sendMessage(prompt: "again")
        XCTAssertNotNil(vm.lastSend)
        vm.startNewChat()
        XCTAssertNil(vm.lastSend)
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
        XCTAssertEqual(mock.prewarmConversationSessionIds, [sessionId],
                       "next-turn prewarm must run after .final with the new session")
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

    func test_ChatViewModel_crisisResource_showsCardPresentation() async throws {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in throw IntelligenceError.crisisResource }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "I want to hurt myself tonight.")
        await waitForLoadingFalse(vm)

        XCTAssertFalse(vm.showingError)
        let assistant = try XCTUnwrap(vm.messages.last)
        XCTAssertEqual(assistant.safetyPresentation, .crisisResource)
        XCTAssertEqual(assistant.content, SafetyRouter.crisisAcknowledgment)
    }

    func test_ChatViewModel_safetyRefusal_showsHardRefuse() async throws {
        let mock = MockChatService()
        mock.sendMessageImpl = { _, _ in throw IntelligenceError.safetyRefusal(.violenceOthers) }

        let vm = ChatViewModel(chatService: mock)
        vm.sendMessage(prompt: "How do I hurt my boss?")
        await waitForLoadingFalse(vm)

        XCTAssertFalse(vm.showingError)
        let assistant = try XCTUnwrap(vm.messages.last)
        XCTAssertEqual(assistant.safetyPresentation, .hardRefuse)
        XCTAssertTrue(assistant.content.contains("I can’t help with that"))
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
