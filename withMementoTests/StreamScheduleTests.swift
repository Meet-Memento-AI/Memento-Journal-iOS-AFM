import XCTest
@testable import withMemento

/// Pins the streaming reveal: `StreamSchedule`'s token rhythm and its
/// guarantees (deterministic, append-only, never ahead of the network,
/// catches up without jumping), and `StreamLayout`'s index space, which the
/// view model and the view must agree on.
final class StreamScheduleTests: XCTestCase {

    private let id = UUID(uuidString: "5F0C2A4E-8B1D-4C3A-9E7F-1A2B3C4D5E6F")!
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let sentence = "Hello there, friend. You wrote about the move twice this week; it stayed with you!"

    private func schedule(_ text: String, at offset: TimeInterval = 0) -> StreamSchedule {
        var s = StreamSchedule(messageID: id, start: start)
        s.append(text, receivedAt: start.addingTimeInterval(offset))
        return s
    }

    // MARK: - Determinism

    func test_sameMessageAndDeltas_giveIdenticalArrivals() {
        XCTAssertEqual(schedule(sentence).arrivals, schedule(sentence).arrivals)
    }

    func test_differentMessages_differ() {
        var other = StreamSchedule(messageID: UUID(), start: start)
        other.append(sentence, receivedAt: start)
        XCTAssertNotEqual(schedule(sentence).arrivals, other.arrivals)
    }

    /// A delta that ends mid-token carries the token over: splitting the same
    /// text across appends at the same instant schedules it identically.
    func test_splitDeltas_matchOneDelta() {
        var split = StreamSchedule(messageID: id, start: start)
        for piece in ["Hel", "lo th", "ere, fri", "end. You wrote about the move twice this week; it stayed with you!"] {
            split.append(piece, receivedAt: start)
        }
        XCTAssertEqual(split.arrivals, schedule(sentence).arrivals)
    }

    // MARK: - Append-only

    func test_append_neverMovesScheduledArrivals() {
        var s = schedule("The first part, ")
        let before = s.arrivals
        s.append("and then the rest.", receivedAt: start.addingTimeInterval(0.4))
        XCTAssertEqual(Array(s.arrivals.prefix(before.count)), before)
        XCTAssertEqual(s.count, "The first part, and then the rest.".count)
    }

    // MARK: - Rhythm

    func test_tokens_neverCrossAWordBoundary_andAreAtMostFiveLong() {
        let s = schedule(sentence)
        let chars = Array(sentence)
        var tokens: [[Character]] = []
        var current: [Character] = []
        var lastStart = s.tokenStart(at: 0)
        for (index, character) in chars.enumerated() {
            if s.tokenStart(at: index) != lastStart {
                tokens.append(current)
                current = []
                lastStart = s.tokenStart(at: index)
            }
            current.append(character)
        }
        tokens.append(current)

        for token in tokens {
            XCTAssertLessThanOrEqual(token.count, 5, "token too long: \(String(token).debugDescription)")
            XCTAssertFalse(token.dropLast().contains(where: \.isWhitespace),
                           "whitespace may only end a token: \(String(token).debugDescription)")
        }
    }

    /// Until the backlog cap engages, which compresses all spacing.
    func test_charactersWithinAToken_are12msApart() {
        let s = schedule(sentence)
        for index in 1..<s.count
        where s.tokenStart(at: index) == s.tokenStart(at: index - 1)
            && s.arrival(at: index) < StreamSchedule.backlogThreshold {
            XCTAssertEqual(s.arrival(at: index) - s.arrival(at: index - 1),
                           StreamSchedule.intraTokenSpacing, accuracy: 1e-9)
        }
    }

    func test_punctuation_addsAPause() {
        let s = schedule(sentence)
        let chars = Array(sentence)
        for index in 1..<chars.count where s.tokenStart(at: index) != s.tokenStart(at: index - 1) {
            let gap = s.arrival(at: index) - s.arrival(at: index - 1)
            // The previous token's last non-space character.
            let last = chars[..<index].last(where: { !$0.isWhitespace })
            switch last {
            case ",":
                XCTAssertGreaterThanOrEqual(gap, StreamSchedule.burstGap + StreamSchedule.commaPause - 1e-9)
            case ".", ";", "!":
                XCTAssertGreaterThanOrEqual(gap, StreamSchedule.burstGap + StreamSchedule.stopPause - 1e-9)
            default:
                XCTAssertLessThanOrEqual(gap, StreamSchedule.gapRange.upperBound + 1e-9)
            }
        }
    }

    // MARK: - Network floor and backlog

    func test_nothingArrivesBeforeItWasReceived() {
        var s = schedule("Fast start ")
        s.append("after a stall", receivedAt: start.addingTimeInterval(2))
        let firstNew = "Fast start ".count
        XCTAssertGreaterThanOrEqual(s.arrival(at: firstNew), 2)
    }

    /// The 300-character burst: the reveal speeds up to catch up and never
    /// jumps — no two consecutive characters arrive out of order.
    func test_burst_catchesUpWithoutJumping() {
        let burst = String(repeating: "Words arrive all at once here. ", count: 10)
        let s = schedule(burst)
        XCTAssertEqual(s.count, burst.count)
        for index in 1..<s.count {
            XCTAssertGreaterThanOrEqual(s.arrival(at: index), s.arrival(at: index - 1))
        }
        let last = s.arrival(at: s.count - 1)
        print("[StreamScheduleTests] 300-character burst reveals in \(last)s")
        XCTAssertLessThan(last, 3.6, "300 characters at once took \(last)s to reveal")
    }

    // MARK: - Completion

    func test_isSettled_onlyAfterFinishAndTheLastFade() {
        var s = schedule("Short reply.")
        let end = start.addingTimeInterval(s.duration)
        XCTAssertFalse(s.isSettled(at: end), "not complete yet")
        s.finish()
        XCTAssertFalse(s.isSettled(at: end.addingTimeInterval(-0.01)))
        XCTAssertTrue(s.isSettled(at: end))
        XCTAssertEqual(s.duration, s.arrival(at: s.count - 1) + StreamSchedule.fade, accuracy: 1e-9)
    }

    func test_arrivalPastTheEnd_isInfinity() {
        XCTAssertEqual(schedule("ab").arrival(at: 2), .infinity)
        XCTAssertEqual(schedule("ab").arrival(at: -1), .infinity)
    }

    func test_settledHistory_isAlreadyOnScreen() {
        let s = StreamSchedule.settled(text: sentence)
        XCTAssertTrue(s.isSettled(at: .distantPast))
        XCTAssertEqual(s.count, sentence.count)
        XCTAssertEqual(s.arrival(at: 0), -.infinity)
    }

    // MARK: - Reconcile

    func test_reconcile_pureExtension_isAnAppend() {
        var reconciled = StreamSchedule(messageID: id, start: start)
        reconciled.reconcile(to: "Hello there, ", receivedAt: start)
        reconciled.reconcile(to: sentence, receivedAt: start)
        XCTAssertEqual(reconciled.arrivals, schedule(sentence).arrivals)
    }

    /// The final re-render can rewrite the tail (reference markers stripped).
    /// The unchanged prefix keeps its arrivals; only the new tail is
    /// rescheduled, from when it was received.
    func test_reconcile_rewrite_keepsThePrefix() {
        var s = schedule("You wrote [1] about it.")
        let kept = "You wrote ".count
        let prefix = Array(s.arrivals.prefix(kept))
        s.reconcile(to: "You wrote about it.", receivedAt: start.addingTimeInterval(3))
        XCTAssertEqual(Array(s.arrivals.prefix(kept)), prefix)
        XCTAssertEqual(s.count, "You wrote about it.".count)
        XCTAssertGreaterThanOrEqual(s.arrival(at: kept), 3)
    }

    func test_reconcile_shrink_dropsTheTail() {
        var s = schedule("Keep this, drop that")
        s.reconcile(to: "Keep this", receivedAt: start)
        XCTAssertEqual(s.count, "Keep this".count)
        XCTAssertEqual(s.arrival(at: s.count), .infinity)
    }

    // MARK: - Layout index space

    func test_layout_countsDisplayedCharactersOnly() {
        let body = "### A heading\nIntro with **bold**.\n\n- first\n- second\n1. ordered"
        let layout = StreamLayout(body: body, heading1: nil, heading2: nil)
        XCTAssertEqual(layout.text, "A heading\nIntro with bold.\n\nfirst\nsecond\nordered")
        for index in layout.blocks.indices.dropLast() {
            XCTAssertEqual(layout.range(ofBlock: index).upperBound + 1, layout.blockStarts[index + 1],
                           "blocks are separated by exactly one index")
        }
        XCTAssertEqual(layout.range(ofBlock: layout.blocks.count - 1).upperBound, layout.text.count)
    }

    /// Headings sit after the body, so a heading that arrives later extends
    /// the schedule instead of shifting the body's indices.
    func test_layout_headingsFollowTheBody() {
        let bodyOnly = StreamLayout(body: "The answer.", heading1: nil, heading2: nil)
        let withHeadings = StreamLayout(body: "The answer.", heading1: "Title", heading2: "Sub")
        XCTAssertTrue(withHeadings.text.hasPrefix(bodyOnly.text))
        XCTAssertEqual(withHeadings.heading1Start, "The answer.\n".count)
        XCTAssertEqual(withHeadings.heading2Start, "The answer.\nTitle\n".count)
    }
}

// MARK: - View model wiring

/// A stream that emits scripted cumulative snapshots back to back, then
/// either finishes or throws.
private final class ScriptedStreamChatService: ChatServiceProtocol {
    let snapshots: [String]
    let failure: Error?

    init(snapshots: [String], failure: Error?) {
        self.snapshots = snapshots
        self.failure = failure
    }

    func sendMessage(_ text: String, sessionId: UUID?) async throws -> ChatResponse {
        ChatResponse(reply: snapshots.last ?? "", heading1: nil, heading2: nil,
                     citedEntryIds: nil, sources: [], sessionId: UUID().uuidString)
    }
    func fetchSessions() async throws -> [ChatSession] { [] }
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO] { [] }
    func deleteSession(sessionId: UUID) async throws {}
    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
        throw URLError(.unsupportedURL)
    }

    func sendMessageStream(_ text: String, sessionId: UUID?, images: [Data], spoken: Bool) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let snapshots = snapshots
        let failure = failure
        return AsyncThrowingStream { continuation in
            for body in snapshots {
                continuation.yield(.delta(body: body, heading1: nil, heading2: nil, sources: []))
            }
            if let failure {
                continuation.finish(throwing: failure)
            } else {
                continuation.yield(.final(ChatResponse(
                    reply: snapshots.last ?? "", heading1: nil, heading2: nil,
                    citedEntryIds: nil, sources: [], sessionId: UUID().uuidString
                )))
                continuation.finish()
            }
        }
    }
}

@MainActor
final class StreamRevealViewModelTests: XCTestCase {

    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    func test_successfulStream_schedulesTheWholeReply_andFinishes() async throws {
        let snapshots = ["Hello ", "Hello there, ", "Hello there, friend."]
        let vm = ChatViewModel(chatService: ScriptedStreamChatService(snapshots: snapshots, failure: nil))
        vm.sendMessage(prompt: "hi")
        await waitUntil { vm.messages.last?.isStreaming == false && vm.messages.last?.schedule?.isComplete == true }

        let reply = try XCTUnwrap(vm.messages.last)
        let schedule = try XCTUnwrap(reply.schedule)
        XCTAssertTrue(schedule.isComplete)
        XCTAssertEqual(schedule.count, "Hello there, friend.".count)
        XCTAssertEqual(vm.revealingMessageID, reply.id, "still revealing right after the stream ends")

        await waitUntil { vm.revealingMessageID == nil }
        XCTAssertNil(vm.revealingMessageID, "the gate clears once the last glyph settles")
        XCTAssertTrue(reply.isRevealSettled())
    }

    /// An error mid-stream: the partial reply stays, ends where the model
    /// did (the coalescer's pending snapshot is applied, not dropped), and
    /// settles normally.
    func test_errorMidStream_keepsTheTail_andFinishes() async throws {
        let snapshots = ["Part one, ", "Part one, part two, ", "Part one, part two, part three"]
        let vm = ChatViewModel(chatService: ScriptedStreamChatService(
            snapshots: snapshots, failure: URLError(.networkConnectionLost)))
        vm.sendMessage(prompt: "hi")
        await waitUntil { !vm.isLoading && vm.messages.last?.isStreaming == false }

        let reply = try XCTUnwrap(vm.messages.last(where: { !$0.isFromUser }))
        XCTAssertEqual(reply.aiOutputContent?.body, snapshots.last)
        let schedule = try XCTUnwrap(reply.schedule)
        XCTAssertTrue(schedule.isComplete)
        XCTAssertEqual(schedule.count, snapshots.last!.count)
    }

    func test_cancel_clearsTheRevealGate() async {
        let vm = ChatViewModel(chatService: ScriptedStreamChatService(
            snapshots: ["A long reply that is still revealing."], failure: nil))
        vm.sendMessage(prompt: "hi")
        await waitUntil { vm.revealingMessageID != nil }
        vm.cancelActiveTasks()
        XCTAssertNil(vm.revealingMessageID, "leaving mid-reveal must not leave send disabled")
    }
}
