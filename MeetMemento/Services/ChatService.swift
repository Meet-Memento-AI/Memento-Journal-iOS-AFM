import Foundation
import Supabase

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

/// Wraps a `chat` edge function failure once its structured body has been
/// decoded, so callers can read `isRetryable`/`serverMessage` directly
/// instead of reaching into the raw `FunctionsError.httpError` payload.
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

// MARK: - Network Retry Configuration

private struct RetryConfig {
    let maxAttempts: Int
    let baseDelayMs: UInt64
    let maxDelayMs: UInt64

    static let `default` = RetryConfig(
        maxAttempts: 3,
        baseDelayMs: 500,
        maxDelayMs: 4000
    )
}

// MARK: - Service

class ChatService {
    static let shared = ChatService()

    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    // MARK: - Native intelligence (Apple Foundation Models)

    /// The on-device intelligence boundary. ChatService itself never imports
    /// FoundationModels — it depends only on the protocol (P3 / REQ-INT-001).
    private let intelligence: IntelligenceService = FoundationModelsIntelligenceService.shared

    /// Reused across citation mapping (avoids a per-source allocation).
    private static let iso8601 = ISO8601DateFormatter()

    /// Loads and decrypts the on-device journal entries the retriever ranks over
    /// (the sole source of truth — no server). Empty when the store is locked or
    /// unavailable, in which case chat answers without journal grounding.
    private func loadLocalEntries() -> [Entry] {
        guard let pin = SecurityService.shared.getPIN() else { return [] }
        return JournalService.shared.loadAllEntriesLocally(withPIN: pin)
    }

    /// Executes an async operation with exponential backoff retry for transient failures
    private func withRetry<T>(
        config: RetryConfig = .default,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var currentDelay = config.baseDelayMs

        for attempt in 1...config.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Check if error is retryable
                let isRetryable = isTransientError(error)

                                AppLogger.log("⚠️ [ChatService] Attempt \(attempt)/\(config.maxAttempts) failed: \(error.localizedDescription)")
                AppLogger.log("   Retryable: \(isRetryable)")

                // Don't retry on final attempt or non-transient errors
                if attempt == config.maxAttempts || !isRetryable {
                    break
                }

                // Exponential backoff with jitter
                let jitter = UInt64.random(in: 0...100)
                let delay = min(currentDelay + jitter, config.maxDelayMs)

                                AppLogger.log("   Retrying in \(delay)ms...")

                try await Task.sleep(nanoseconds: delay * 1_000_000)
                currentDelay = min(currentDelay * 2, config.maxDelayMs)
            }
        }

        throw lastError ?? NSError(
            domain: "ChatService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error after retries"]
        )
    }

    /// Determines if an error is transient and should be retried
    private func isTransientError(_ error: Error) -> Bool {
        let nsError = error as NSError

        // URL session errors that are transient
        let transientURLErrors: Set<Int> = [
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorNotConnectedToInternet,
            NSURLErrorSecureConnectionFailed,
            -1001, // kCFURLErrorTimedOut
            -1009  // kCFURLErrorNotConnectedToInternet
        ]

        if nsError.domain == NSURLErrorDomain && transientURLErrors.contains(nsError.code) {
            return true
        }

        // HTTP 5xx errors are retryable. 429 is NOT: the server's rate-limit
        // window (minutes to a day, see spec-004 R2) is far longer than this
        // backoff's few seconds, so retrying just delays the same rejection
        // and burns the user's remaining quota. Let it surface immediately.
        if let httpCode = (error as? URLError)?.errorCode {
            return httpCode >= 500
        }

        // spec-010: the `chat` function's structured error body is the
        // authoritative signal when present — it already encodes exactly
        // what this classification is trying to approximate (e.g. a 502
        // LLM_UNAVAILABLE is retryable, a 400 invalid-session is not).
        if case let FunctionsError.httpError(_, data) = error,
           let body = try? JSONDecoder().decode(ChatServerError.self, from: data) {
            return body.retryable
        }

        return false
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

    // MARK: - Chat Feedback

    /// Submits feedback (thumbs up/down) for a message
    /// Returns the resulting feedback type (nil if toggled off)
    func submitFeedback(messageId: UUID, type: FeedbackType) async throws -> FeedbackType? {
                AppLogger.log("👍 [ChatService] Submitting \(type.rawValue) feedback for message \(messageId.uuidString.prefix(8))...")

        struct FeedbackRequest: Codable {
            let messageId: String
            let feedbackType: String
        }

        struct FeedbackResponse: Codable {
            let success: Bool
            let feedbackType: String?
            let action: String
        }

        let request = FeedbackRequest(
            messageId: messageId.uuidString,
            feedbackType: type.rawValue
        )

        // Refresh session to ensure we have a valid access token
        // (the SDK's auto-refresh doesn't trigger when manually extracting tokens)
        let session = try await client.auth.refreshSession()

        let response: FeedbackResponse = try await withRetry {
            try await self.client.functions.invoke(
                "chat-feedback",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: request
                )
            )
        }

                AppLogger.log("✅ [ChatService] Feedback \(response.action): \(response.feedbackType ?? "none")")

        guard let feedbackTypeString = response.feedbackType else {
            return nil
        }
        return FeedbackType(rawValue: feedbackTypeString)
    }

    /// Fetches existing feedback for a list of message IDs
    /// Returns a dictionary mapping message ID to feedback type
    func fetchFeedback(messageIds: [UUID]) async throws -> [UUID: FeedbackType] {
        guard let userId = client.auth.currentUser?.id else {
                        AppLogger.log("⚠️ [ChatService] Cannot fetch feedback — no authenticated user")
            return [:]
        }

        guard !messageIds.isEmpty else {
            return [:]
        }

                AppLogger.log("📋 [ChatService] Fetching feedback for \(messageIds.count) messages...")

        struct FeedbackRow: Codable {
            let messageId: UUID
            let feedbackType: String

            enum CodingKeys: String, CodingKey {
                case messageId = "message_id"
                case feedbackType = "feedback_type"
            }
        }

        let messageIdStrings = messageIds.map { $0.uuidString }

        let response: [FeedbackRow] = try await client
            .from("chat_feedback")
            .select("message_id, feedback_type")
            .eq("user_id", value: userId)
            .in("message_id", values: messageIdStrings)
            .execute()
            .value

        var result: [UUID: FeedbackType] = [:]
        for row in response {
            if let feedbackType = FeedbackType(rawValue: row.feedbackType) {
                result[row.messageId] = feedbackType
            }
        }

                AppLogger.log("✅ [ChatService] Fetched \(result.count) feedback entries")

        return result
    }
}

extension ChatService: ChatServiceProtocol {}
