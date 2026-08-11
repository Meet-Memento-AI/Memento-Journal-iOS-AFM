import Foundation
@testable import MeetMemento

final class MockChatService: ChatServiceProtocol {
    var sendMessageImpl: ((String, UUID?) async throws -> ChatResponse)?
    /// When set, overrides the protocol's default one-shot streaming wrap —
    /// yields these events in order, then finishes (throwing `streamError` at
    /// the end if set).
    var streamEvents: [ChatStreamEvent]?
    var streamError: Error?
    var fetchSessionsImpl: (() async throws -> [ChatSession])?
    var loadSessionMessagesImpl: ((UUID) async throws -> [ChatMessageDTO])?
    var deleteSessionImpl: ((UUID) async throws -> Void)?
    var summarizeChatImpl: (([ChatMessage], UUID?) async throws -> ChatSummaryResponse)?

    func sendMessage(_ text: String, sessionId: UUID?) async throws -> ChatResponse {
        guard let impl = sendMessageImpl else {
            throw NSError(domain: "MockChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "sendMessage not configured"])
        }
        return try await impl(text, sessionId)
    }

    func sendMessageStreaming(_ text: String, sessionId: UUID?) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        // Scripted stream when configured; else the default one-shot wrap.
        guard streamEvents != nil || streamError != nil else {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let response = try await self.sendMessage(text, sessionId: sessionId)
                        continuation.yield(.completed(response))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        let events = streamEvents ?? []
        let error = streamError
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            if let error { continuation.finish(throwing: error) } else { continuation.finish() }
        }
    }

    func fetchSessions() async throws -> [ChatSession] {
        if let impl = fetchSessionsImpl { return try await impl() }
        return []
    }

    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        guard let impl = loadSessionMessagesImpl else { return [] }
        return try await impl(sessionId)
    }

    func deleteSession(sessionId: UUID) async throws {
        if let impl = deleteSessionImpl { try await impl(sessionId) }
    }

    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
        guard let impl = summarizeChatImpl else {
            throw NSError(domain: "MockChatService", code: -2, userInfo: [NSLocalizedDescriptionKey: "summarize not configured"])
        }
        return try await impl(messages, sessionId)
    }
}
