import XCTest
@testable import MeetMemento

/// Covers the streaming plumbing added for chat-speed: the protocol-level
/// `askStream` / `sendMessageStream` must emit at least one `.delta` before the
/// terminal `.final`, and the final payload must match the one-shot result. The
/// real on-device streaming needs Apple Intelligence hardware; these exercise the
/// default-extension bridge (ask → delta + final) that mocks and non-streaming
/// callers rely on, so the ViewModel's live-update path is covered off-device.
final class ChatStreamingTests: XCTestCase {

    func test_askStream_emitsDeltaBeforeFinal() async throws {
        let intelligence = MockIntelligenceService()

        var events: [AskStreamEvent] = []
        for try await event in intelligence.askStream("hello", history: [], entries: []) {
            events.append(event)
        }

        XCTAssertGreaterThanOrEqual(events.count, 2, "expected at least a delta and a final")

        guard case .delta(let bodySoFar, _, _, _) = events.first else {
            return XCTFail("first event should be a .delta, got \(String(describing: events.first))")
        }
        guard case .final(let result) = events.last else {
            return XCTFail("last event should be a .final, got \(String(describing: events.last))")
        }

        // No .final may appear before the terminal position.
        for event in events.dropLast() {
            if case .final = event { XCTFail(".final emitted before the stream ended") }
        }

        XCTAssertEqual(result.body, "mock reply")
        XCTAssertEqual(bodySoFar, result.body, "delta body should match the final body via the bridge")
    }

    func test_sendMessageStream_emitsDeltaThenFinal() async throws {
        let chat = MockChatService()
        chat.sendMessageImpl = { text, _ in
            ChatResponse(
                reply: "echo: \(text)",
                heading1: nil,
                heading2: nil,
                citedEntryIds: nil,
                sources: [],
                sessionId: UUID().uuidString
            )
        }

        var events: [ChatStreamEvent] = []
        for try await event in chat.sendMessageStream("ping", sessionId: nil) {
            events.append(event)
        }

        XCTAssertGreaterThanOrEqual(events.count, 2, "expected at least a delta and a final")

        guard case .delta = events.first else {
            return XCTFail("first event should be a .delta, got \(String(describing: events.first))")
        }
        guard case .final(let response) = events.last else {
            return XCTFail("last event should be a .final, got \(String(describing: events.last))")
        }

        XCTAssertEqual(response.reply, "echo: ping")
    }
}
