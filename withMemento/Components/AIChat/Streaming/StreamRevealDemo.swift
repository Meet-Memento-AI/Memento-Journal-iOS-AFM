//
//  StreamRevealDemo.swift
//  withMemento
//
//  DEBUG-only chat service that streams a long reply on a hostile rhythm, to
//  exercise the reveal by eye: random 1–8 character deltas 10–300ms apart,
//  one 2s stall, and one 300-character burst. Launch with
//  `-StreamRevealDemo` to use it in the simulator, or open the
//  "Streaming reveal" preview. Compiled out of release builds.
//

#if DEBUG
import Foundation

final class StreamRevealDemoService: ChatServiceProtocol {

    static let launchArgument = "-StreamRevealDemo"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static let reply = """
    You have come back to the same few themes all month, and each time you write about them the tone shifts a \
    little. Early on the move felt like something being done to you; by the third week you were describing it \
    as a choice, even a relief. That change is worth noticing, because it happened quietly, between entries, \
    without you naming it.

    The evenings stand out too. Most of what you wrote after nine was about rest, or the lack of it, and \
    almost none of it was about work — which is unusual for you. It reads like you were giving yourself \
    permission to stop thinking about the job once the day was done, and it seems to have helped: the mornings \
    after those entries are lighter, shorter, and more curious about what comes next.

    A few things you might carry forward:

    - Keep the evening cut-off, even on busy days.
    - Notice when "should" shows up in your writing.
    - Write one line about the move each week, just to see where it goes.

    None of this needs fixing. It is simply what the last month looks like from the outside, and you get to \
    decide what it means.
    """

    func sendMessage(_ text: String, sessionId: UUID?) async throws -> ChatResponse {
        ChatResponse(
            reply: Self.reply,
            heading1: nil,
            heading2: nil,
            citedEntryIds: nil,
            sources: [],
            sessionId: UUID().uuidString
        )
    }

    func fetchSessions() async throws -> [ChatSession] { [] }
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO] { [] }
    func deleteSession(sessionId: UUID) async throws {}

    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
        throw IntelligenceError.guardrailRefusal
    }

    /// Cumulative snapshots, as the live service emits them.
    func sendMessageStream(
        _ text: String,
        sessionId: UUID?,
        images: [Data],
        spoken: Bool
    ) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let characters = Array(Self.reply)
        let stallAt = characters.count * 2 / 10
        let burstAt = characters.count * 5 / 10
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await Self.stream(characters, stallAt: stallAt, burstAt: burstAt, into: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func stream(
        _ characters: [Character],
        stallAt: Int,
        burstAt: Int,
        into continuation: AsyncThrowingStream<ChatStreamEvent, Error>.Continuation
    ) async throws {
        var rng = SystemRandomNumberGenerator()
        var sent = 0
        var stalled = false
        var bursted = false
        while sent < characters.count {
            var delay = Double.random(in: 0.010...0.300, using: &rng)
            var step = Int.random(in: 1...8, using: &rng)
            if !stalled, sent >= stallAt {
                stalled = true
                delay = 2.0
            } else if !bursted, sent >= burstAt {
                bursted = true
                step = 300
            }
            try await Task.sleep(for: .seconds(delay))
            sent = min(characters.count, sent + step)
            continuation.yield(.delta(
                body: String(characters[..<sent]),
                heading1: nil,
                heading2: nil,
                sources: []
            ))
        }
        continuation.yield(.final(ChatResponse(
            reply: Self.reply,
            heading1: nil,
            heading2: nil,
            citedEntryIds: nil,
            sources: [],
            sessionId: UUID().uuidString
        )))
        continuation.finish()
    }
}
#endif
