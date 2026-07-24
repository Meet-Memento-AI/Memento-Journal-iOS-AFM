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

// MARK: - Request Types

private struct ChatRequestBody: Codable {
    let message: String
    let sessionId: String?
}

// MARK: - Summary Types

struct ChatSummaryRequest: Codable {
    let sessionId: String?
    let messages: [SummaryMessage]
}

struct SummaryMessage: Codable {
    let role: String
    let content: String
}

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
        let requestBody = ChatRequestBody(message: text, sessionId: sessionId?.uuidString)

                AppLogger.log("💬 [ChatService] Sending message to chat Edge Function (session: \(sessionId?.uuidString.prefix(8) ?? "new"))...")

        // Refresh session to ensure we have a valid access token
        // (the SDK's auto-refresh doesn't trigger when manually extracting tokens)
        let session = try await client.auth.refreshSession()

        do {
            let response: ChatResponse = try await withRetry {
                try await self.client.functions.invoke(
                    "chat",
                    options: FunctionInvokeOptions(
                        headers: ["Authorization": "Bearer \(session.accessToken)"],
                        body: requestBody
                    )
                )
            }

                    AppLogger.log("✅ [ChatService] Received reply (\(response.reply.count) chars), \(response.sources.count) sources, cited: \(response.citedEntryIds?.count ?? 0), session: \(response.sessionId.prefix(8))...")

            return response
        } catch {
            throw Self.mapServerError(error)
        }
    }

    /// Decodes the spec-010 structured error body out of a raw
    /// `FunctionsError.httpError`, if present, so callers get a typed
    /// `ChatServiceError` (message + retryable + code) instead of having to
    /// reach into the raw response bytes themselves. Errors that aren't an
    /// HTTP failure with that body shape (network errors, legacy endpoints)
    /// pass through unchanged.
    private static func mapServerError(_ error: Error) -> Error {
        guard case let FunctionsError.httpError(code, data) = error,
              let body = try? JSONDecoder().decode(ChatServerError.self, from: data) else {
            return error
        }
        return ChatServiceError.server(body, httpStatus: code)
    }

    // MARK: - Embedding Trigger

    /// Triggers embedding generation for a specific journal entry
    /// Called after saving entries to ensure embeddings are generated
    func triggerEmbedding(entryId: UUID) async throws {
                AppLogger.log("🔄 [ChatService] Triggering embedding for entry \(entryId.uuidString.prefix(8))...")

        struct EmbedRequest: Codable {
            let entryId: String
        }

        let request = EmbedRequest(entryId: entryId.uuidString)

        // Refresh session to ensure we have a valid access token
        // (the SDK's auto-refresh doesn't trigger when manually extracting tokens)
        let session = try await client.auth.refreshSession()

        try await withRetry {
            try await self.client.functions.invoke(
                "sync-embedding",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: request
                )
            )
        }

                AppLogger.log("✅ [ChatService] Embedding triggered for entry \(entryId.uuidString.prefix(8))")
    }

    // MARK: - History Management

    func clearHistory() async throws {
        guard let userId = client.auth.currentUser?.id else {
                        AppLogger.log("⚠️ [ChatService] Cannot clear history — no authenticated user")
            return
        }

        try await client
            .from("chat_messages")
            .delete()
            .eq("user_id", value: userId)
            .execute()

                AppLogger.log("🗑️ [ChatService] Chat history cleared for user \(userId.uuidString.prefix(8))...")
    }

    // MARK: - Session Management

    /// Fetches all chat sessions for the current user, sorted by most recent first
    func fetchSessions() async throws -> [ChatSession] {
        guard let userId = client.auth.currentUser?.id else {
                        AppLogger.log("⚠️ [ChatService] Cannot fetch sessions — no authenticated user")
            return []
        }

                AppLogger.log("📋 [ChatService] Fetching chat sessions...")

        let response: [ChatSession] = try await client
            .from("chat_sessions")
            .select()
            .eq("user_id", value: userId)
            .order("updated_at", ascending: false)
            .execute()
            .value

                AppLogger.log("✅ [ChatService] Fetched \(response.count) sessions")

        return response
    }

    /// Loads all messages for a specific session
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        guard let userId = client.auth.currentUser?.id else {
                        AppLogger.log("⚠️ [ChatService] Cannot load session messages — no authenticated user")
            return []
        }

                AppLogger.log("📖 [ChatService] Loading messages for session \(sessionId.uuidString.prefix(8))...")

        let response: [ChatMessageDTO] = try await client
            .from("chat_messages")
            .select("id, role, content, created_at")
            .eq("session_id", value: sessionId)
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .execute()
            .value

                AppLogger.log("✅ [ChatService] Loaded \(response.count) messages")

        return response
    }

    /// Deletes a chat session and all its messages (cascade delete via FK)
    func deleteSession(sessionId: UUID) async throws {
        guard let userId = client.auth.currentUser?.id else {
                        AppLogger.log("⚠️ [ChatService] Cannot delete session — no authenticated user")
            return
        }

                AppLogger.log("🗑️ [ChatService] Deleting session \(sessionId.uuidString.prefix(8))...")

        try await client
            .from("chat_sessions")
            .delete()
            .eq("id", value: sessionId)
            .eq("user_id", value: userId)
            .execute()

                AppLogger.log("✅ [ChatService] Session deleted")
    }

    // MARK: - Chat Summary

    /// Summarizes a chat conversation into a journal entry using AI
    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
                AppLogger.log("📝 [ChatService] Summarizing chat (\(messages.count) messages)...")

        let summaryMessages = messages.map { msg in
            SummaryMessage(role: msg.isFromUser ? "user" : "assistant", content: msg.content)
        }

        let requestBody = ChatSummaryRequest(
            sessionId: sessionId?.uuidString,
            messages: summaryMessages
        )

        // Refresh session to ensure we have a valid access token
        // (the SDK's auto-refresh doesn't trigger when manually extracting tokens)
        let session = try await client.auth.refreshSession()

        let response: ChatSummaryResponse = try await withRetry {
            try await self.client.functions.invoke(
                "summarize-chat",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: requestBody
                )
            )
        }

                AppLogger.log("✅ [ChatService] Summary generated (\(response.content.count) chars)")

        return response
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
