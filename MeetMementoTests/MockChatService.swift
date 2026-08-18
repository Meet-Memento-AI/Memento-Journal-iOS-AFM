import Foundation
@testable import MeetMemento

final class MockChatService: ChatServiceProtocol {
    var sendMessageImpl: ((String, UUID?) async throws -> ChatResponse)?
    var fetchSessionsImpl: (() async throws -> [ChatSession])?
    var loadSessionMessagesImpl: ((UUID) async throws -> [ChatMessageDTO])?
    var deleteSessionImpl: ((UUID) async throws -> Void)?
    var summarizeChatImpl: (([ChatMessage], UUID?) async throws -> ChatSummaryResponse)?
    private(set) var prewarmConversationSessionIds: [UUID?] = []

    func sendMessage(_ text: String, sessionId: UUID?) async throws -> ChatResponse {
        guard let impl = sendMessageImpl else {
            throw NSError(domain: "MockChatService", code: -1, userInfo: [NSLocalizedDescriptionKey: "sendMessage not configured"])
        }
        return try await impl(text, sessionId)
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

    func prewarmConversation(sessionId: UUID?) {
        prewarmConversationSessionIds.append(sessionId)
    }

    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
        guard let impl = summarizeChatImpl else {
            throw NSError(domain: "MockChatService", code: -2, userInfo: [NSLocalizedDescriptionKey: "summarize not configured"])
        }
        return try await impl(messages, sessionId)
    }
}
