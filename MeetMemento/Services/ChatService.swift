import Foundation
import Supabase

// MARK: - Response Types

/// Decoded `chat` Edge Function JSON. `sources` may be empty when retrieval was skipped, no matches were found,
/// or the model did not cite journal entries — the citations UI should treat an empty list as “no citations.”
struct ChatResponse: Codable {
    let reply: String
    let heading1: String?
    let heading2: String?
    /// Inline citations with ref number, entry UUID, theme, and date.
    let inlineCitations: [InlineCitation]?
    /// Entry UUIDs the model cited; mirrors server `cited_entry_ids` (optional for backward compatibility).
    let citedEntryIds: [String]?
    let sources: [ChatSource]
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case reply, heading1, heading2, sources, sessionId
        case inlineCitations = "inline_citations"
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

/// Inline citation from the backend: maps a ref number to a journal entry UUID + theme.
struct InlineCitation: Codable, Hashable {
    let ref: Int
    let entryId: String
    let theme: String
    let date: String?

    enum CodingKeys: String, CodingKey {
        case ref
        case entryId = "entry_id"
        case theme
        case date
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
    let title: String
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

                #if DEBUG
                print("⚠️ [ChatService] Attempt \(attempt)/\(config.maxAttempts) failed: \(error.localizedDescription)")
                print("   Retryable: \(isRetryable)")
                #endif

                // Don't retry on final attempt or non-transient errors
                if attempt == config.maxAttempts || !isRetryable {
                    break
                }

                // Exponential backoff with jitter
                let jitter = UInt64.random(in: 0...100)
                let delay = min(currentDelay + jitter, config.maxDelayMs)

                #if DEBUG
                print("   Retrying in \(delay)ms...")
                #endif

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

        // HTTP 5xx errors and 429 (rate limit) are retryable
        if let httpCode = (error as? URLError)?.errorCode {
            return httpCode >= 500 || httpCode == 429
        }

        return false
    }

    func sendMessage(_ text: String, sessionId: UUID? = nil) async throws -> ChatResponse {
        let requestBody = ChatRequestBody(message: text, sessionId: sessionId?.uuidString)

        #if DEBUG
        print("💬 [ChatService] Sending message to chat Edge Function (session: \(sessionId?.uuidString.prefix(8) ?? "new"))...")
        #endif

        let response: ChatResponse = try await withRetry {
            try await self.client.functions.invoke(
                "chat",
                options: FunctionInvokeOptions(body: requestBody)
            )
        }

        #if DEBUG
        print("✅ [ChatService] Received reply (\(response.reply.count) chars), \(response.sources.count) sources, cited: \(response.citedEntryIds?.count ?? 0), session: \(response.sessionId.prefix(8))...")
        #endif

        return response
    }

    // MARK: - Embedding Trigger

    /// Triggers embedding generation for a specific journal entry
    /// Called after saving entries to ensure embeddings are generated
    func triggerEmbedding(entryId: UUID) async throws {
        #if DEBUG
        print("🔄 [ChatService] Triggering embedding for entry \(entryId.uuidString.prefix(8))...")
        #endif

        struct EmbedRequest: Codable {
            let entryId: String
        }

        let request = EmbedRequest(entryId: entryId.uuidString)

        try await withRetry {
            try await self.client.functions.invoke(
                "sync-embedding",
                options: FunctionInvokeOptions(body: request)
            )
        }

        #if DEBUG
        print("✅ [ChatService] Embedding triggered for entry \(entryId.uuidString.prefix(8))")
        #endif
    }

    // MARK: - History Management

    func clearHistory() async throws {
        guard let userId = client.auth.currentUser?.id else {
            #if DEBUG
            print("⚠️ [ChatService] Cannot clear history — no authenticated user")
            #endif
            return
        }

        try await client
            .from("chat_messages")
            .delete()
            .eq("user_id", value: userId)
            .execute()

        #if DEBUG
        print("🗑️ [ChatService] Chat history cleared for user \(userId.uuidString.prefix(8))...")
        #endif
    }

    // MARK: - Session Management

    /// Fetches all chat sessions for the current user, sorted by most recent first
    func fetchSessions() async throws -> [ChatSession] {
        guard let userId = client.auth.currentUser?.id else {
            #if DEBUG
            print("⚠️ [ChatService] Cannot fetch sessions — no authenticated user")
            #endif
            return []
        }

        #if DEBUG
        print("📋 [ChatService] Fetching chat sessions...")
        #endif

        let response: [ChatSession] = try await client
            .from("chat_sessions")
            .select()
            .eq("user_id", value: userId)
            .order("updated_at", ascending: false)
            .execute()
            .value

        #if DEBUG
        print("✅ [ChatService] Fetched \(response.count) sessions")
        #endif

        return response
    }

    /// Loads all messages for a specific session
    func loadSessionMessages(sessionId: UUID) async throws -> [ChatMessageDTO] {
        guard let userId = client.auth.currentUser?.id else {
            #if DEBUG
            print("⚠️ [ChatService] Cannot load session messages — no authenticated user")
            #endif
            return []
        }

        #if DEBUG
        print("📖 [ChatService] Loading messages for session \(sessionId.uuidString.prefix(8))...")
        #endif

        let response: [ChatMessageDTO] = try await client
            .from("chat_messages")
            .select("id, role, content, created_at")
            .eq("session_id", value: sessionId)
            .eq("user_id", value: userId)
            .order("created_at", ascending: true)
            .execute()
            .value

        #if DEBUG
        print("✅ [ChatService] Loaded \(response.count) messages")
        #endif

        return response
    }

    /// Deletes a chat session and all its messages (cascade delete via FK)
    func deleteSession(sessionId: UUID) async throws {
        guard let userId = client.auth.currentUser?.id else {
            #if DEBUG
            print("⚠️ [ChatService] Cannot delete session — no authenticated user")
            #endif
            return
        }

        #if DEBUG
        print("🗑️ [ChatService] Deleting session \(sessionId.uuidString.prefix(8))...")
        #endif

        try await client
            .from("chat_sessions")
            .delete()
            .eq("id", value: sessionId)
            .eq("user_id", value: userId)
            .execute()

        #if DEBUG
        print("✅ [ChatService] Session deleted")
        #endif
    }

    // MARK: - Chat Summary

    /// Summarizes a chat conversation into a journal entry using AI
    func summarizeChat(messages: [ChatMessage], sessionId: UUID?) async throws -> ChatSummaryResponse {
        #if DEBUG
        print("📝 [ChatService] Summarizing chat (\(messages.count) messages)...")
        #endif

        let summaryMessages = messages.map { msg in
            SummaryMessage(role: msg.isFromUser ? "user" : "assistant", content: msg.content)
        }

        let requestBody = ChatSummaryRequest(
            sessionId: sessionId?.uuidString,
            messages: summaryMessages
        )

        let response: ChatSummaryResponse = try await withRetry {
            try await self.client.functions.invoke(
                "summarize-chat",
                options: FunctionInvokeOptions(body: requestBody)
            )
        }

        #if DEBUG
        print("✅ [ChatService] Summary generated: \"\(response.title.prefix(30))...\"")
        #endif

        return response
    }
}

extension ChatService: ChatServiceProtocol {}
