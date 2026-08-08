import Foundation

// MARK: - Response Types

/// Decoded `chat` Edge Function JSON. `sources` may be empty when retrieval was skipped, no matches were found,
/// or the model did not cite journal entries — the citations UI should treat an empty list as "no citations."
struct ChatResponse: Codable {
    let reply: String
    let heading1: String?
    let heading2: String?
    /// Entry UUIDs the model cited; mirrors server `cited_entry_ids` (optional for backward compatibility).
    let citedEntryIds: [String]?
    let sources: [ChatSource]
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case reply, heading1, heading2, sources, sessionId
        case citedEntryIds = "cited_entry_ids"
    }
}

struct ChatSource: Codable, Equatable {
    let id: String
    let createdAt: String
    let preview: String

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case preview
    }
}

/// Structured error body the `chat` edge function returns on failure
/// (spec-010): `{error, code, retryable}` instead of masquerading as a 200.
struct ChatServerError: Codable {
    let error: String
    let code: String
    let retryable: Bool
}

/// Structured chat error type. Retained for the error-message mapping in
/// `ChatViewModel`; the on-device generation path throws `IntelligenceError`
/// rather than this, so `.server` is currently unused (kept for shape).
enum ChatServiceError: Error, LocalizedError {
    case server(ChatServerError, httpStatus: Int)

    var errorDescription: String? {
        switch self {
        case .server(let body, _):
            return body.error
        }
    }

    var isRetryable: Bool {
        switch self {
        case .server(let body, _):
            return body.retryable
        }
    }

    var code: String {
        switch self {
        case .server(let body, _):
            return body.code
        }
    }
}

// MARK: - Summary Types

struct ChatSummaryResponse: Codable {
    let title: String?
    let content: String
}

// MARK: - Service protocol (enables unit tests with mocks)

protocol ChatServiceProtocol: AnyObject {
    func sendMessage(_ text: String, sessionId: UUID?) async throws -> ChatResponse
    func fetchSessions() async throws -> [ChatSession]
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO]
    func deleteSession(sessionId: UUID) async throws
    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse
}

// MARK: - Service

class ChatService {
    static let shared = ChatService()

    // MARK: - Native intelligence (Apple Foundation Models)

    /// The on-device intelligence boundary. ChatService itself never imports
    /// FoundationModels — it depends only on the protocol (P3 / REQ-INT-001).
    private let intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared

    /// Reused across citation mapping (avoids a per-source allocation).
    private static let iso8601 = ISO8601DateFormatter()

    /// Loads and decrypts the on-device journal entries the retriever ranks over
    /// (the sole source of truth — no server).
    ///
    /// This used to bail out entirely when `SecurityService.getPIN()` returned
    /// nil, which meant a Keychain miss silently stripped chat of all journal
    /// grounding — the model would answer confidently from nothing. Entries are
    /// now read under the Keychain-resident data key; the PIN is passed only so
    /// content still encrypted under the legacy PBKDF2(PIN) scheme can be read
    /// and rewritten.
    private func loadLocalEntries() -> [Entry] {
        JournalService.shared.loadAllEntriesLocally(legacyPIN: SecurityService.shared.getPIN())
    }

    func sendMessage(_ text: String, sessionId: UUID? = nil) async throws -> ChatResponse {
        let conversationId = sessionId ?? UUID()
                AppLogger.log("💬 [ChatService] Generating on-device reply (conversation: \(conversationId.uuidString.prefix(8)))...")

        // History comes from the on-device store (the single source of truth),
        // so reopening a saved conversation or relaunching keeps full context —
        // the fix for the model losing the thread / re-greeting each turn.
        let history = Self.historyTurns(from: LocalChatStore.shared.messages(for: conversationId))
        let entries = loadLocalEntries()

        let result = try await intelligence.ask(text, history: history, entries: entries)

        let sources = result.citations.map { citation in
            ChatSource(
                id: citation.entryId.uuidString,
                createdAt: Self.iso8601.string(from: citation.entryDate),
                preview: citation.excerpt
            )
        }

                AppLogger.log("✅ [ChatService] Reply (\(result.body.count) chars), \(sources.count) citations, zone: \(String(describing: result.zoneUsed)), prompt: \(result.promptVersion)")

        // Persist locally so the conversation survives relaunch and shows in the
        // history list (multiple chat windows). The assistant turn is stored in
        // the {heading1,heading2,body,sources} JSON shape the chat UI parses on load.
        LocalChatStore.shared.upsertSession(id: conversationId, title: String(text.prefix(100)))
        LocalChatStore.shared.appendMessage(role: "user", content: text, to: conversationId)
        LocalChatStore.shared.appendMessage(
            role: "assistant",
            content: Self.assistantContentJSON(body: result.body, heading1: result.heading1, heading2: result.heading2, sources: sources),
            to: conversationId
        )

        return ChatResponse(
            reply: result.body,
            heading1: result.heading1,
            heading2: result.heading2,
            citedEntryIds: result.citations.map { $0.entryId.uuidString },
            sources: sources,
            sessionId: conversationId.uuidString
        )
    }

    // MARK: - History Management

    func clearHistory() async throws {
        LocalChatStore.shared.clear()
                AppLogger.log("🗑️ [ChatService] Local chat history cleared")
    }

    // MARK: - Session Management (local, on-device)

    /// All chat sessions, most recently updated first.
    func fetchSessions() async throws -> [ChatSession] {
        let sessions = LocalChatStore.shared.sessions()
                AppLogger.log("📋 [ChatService] Fetched \(sessions.count) local sessions")
        return sessions
    }

    /// All messages for a session, oldest first.
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        let messages = LocalChatStore.shared.messages(for: sessionId)
                AppLogger.log("📖 [ChatService] Loaded \(messages.count) local messages for \(sessionId.uuidString.prefix(8))")
        return messages
    }

    /// Deletes a chat session and its messages.
    func deleteSession(sessionId: UUID) async throws {
        LocalChatStore.shared.deleteSession(sessionId)
                AppLogger.log("🗑️ [ChatService] Deleted local session \(sessionId.uuidString.prefix(8))")
    }

    /// Rebuilds the prior conversation as `[ChatTurn]` from the stored messages,
    /// unwrapping each assistant message's `{…, body}` JSON back to plain text.
    static func historyTurns(from dtos: [ChatMessageDTO]) -> [ChatTurn] {
        dtos.map { dto in
            dto.role == "user"
                ? ChatTurn(role: .user, text: dto.content)
                : ChatTurn(role: .assistant, text: unwrapAssistantBody(dto.content))
        }
    }

    static func unwrapAssistantBody(_ content: String) -> String {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = object["body"] as? String else {
            return content   // legacy plain text
        }
        return body
    }

    /// Builds the assistant message content in the JSON shape the chat UI parses
    /// on load (`ChatViewModel.extractBodyContent`): body + optional headings +
    /// sources so citations re-render for reloaded conversations.
    static func assistantContentJSON(body: String, heading1: String?, heading2: String?, sources: [ChatSource]) -> String {
        var object: [String: Any] = ["body": body]
        if let heading1 { object["heading1"] = heading1 }
        if let heading2 { object["heading2"] = heading2 }
        object["sources"] = sources.map { ["id": $0.id, "created_at": $0.createdAt, "preview": $0.preview] }
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else {
            return body
        }
        return json
    }

    // MARK: - Chat Summary

    /// Summarizes a chat conversation into a journal entry, on-device.
    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
                AppLogger.log("📝 [ChatService] Summarizing chat on-device (\(messages.count) messages)...")

        let turns = messages.map { ChatTurn(role: $0.isFromUser ? .user : .assistant, text: $0.content) }
        let content = try await intelligence.summarizeConversation(turns)

                AppLogger.log("✅ [ChatService] Summary generated (\(content.count) chars)")

        return ChatSummaryResponse(title: nil, content: content)
    }

    // MARK: - Chat Feedback (local-only stub)

    // Thumbs up/down had a server backend (a feedback endpoint + table).
    // The backend was removed from the product, so feedback is now
    // UI-only: `ChatViewModel` already tracks the up/down state in memory for
    // the session. These stubs keep that surface working without persistence —
    // reimplement on-device if feedback needs to survive relaunches.

    /// No-op: records nothing server-side, echoes the submitted type back so the
    /// in-memory UI state is treated as applied.
    func submitFeedback(messageId: UUID, type: FeedbackType) async throws -> FeedbackType? {
        AppLogger.log("👍 [ChatService] Feedback \(type.rawValue) (local-only, not persisted) for \(messageId.uuidString.prefix(8))")
        return type
    }

    /// No persisted feedback to restore (no backend) — always empty.
    func fetchFeedback(messageIds: [UUID]) async throws -> [UUID: FeedbackType] {
        [:]
    }
}

extension ChatService: ChatServiceProtocol {}
