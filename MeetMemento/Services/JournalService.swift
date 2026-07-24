
import Foundation
import Supabase

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

class JournalService {
    static let shared = JournalService()

    /// Internal (not private) so tests can decrypt what this instance wrote
    /// via its own injected `EncryptionService`, without a Keychain-backed
    /// round trip through `.shared`. Defaults to the shared, real-Keychain
    /// instance in production.
    let encryptionService: EncryptionService

    init(encryptionService: EncryptionService = .shared) {
        self.encryptionService = encryptionService
    }

    private var client: SupabaseClient {
        SupabaseService.shared.client
    }

    // MARK: - Retry Helper

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

                                AppLogger.log("⚠️ [JournalService] Attempt \(attempt)/\(config.maxAttempts) failed: \(error.localizedDescription)")
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
            domain: "JournalService",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unknown error after retries"]
        )
    }

    /// Determines if an error is transient and should be retried.
    /// Internal (not private) so tests can exercise the classification
    /// directly without needing a live network call to fail.
    func isTransientError(_ error: Error) -> Bool {
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

    /// Fetches all non-deleted journal entries for the current user, ordered by creation date (newest first).
    func fetchEntries() async throws -> [JournalEntry] {
        guard let userId = client.auth.currentUser?.id else {
            return []
        }

        let response: [JournalEntryDTO] = try await withRetry {
            try await self.client
                .from("journal_entries")
                .select()
                .eq("user_id", value: userId)
                .eq("is_deleted", value: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        }

        return response.compactMap { $0.toDomain() }
    }

    /// Creates a new journal entry and returns the created entry with server-assigned values.
    @discardableResult
    func createEntry(_ entry: JournalEntry) async throws -> JournalEntry {
        let dto = JournalEntryDTO(from: entry)
        let response: [JournalEntryDTO] = try await withRetry {
            try await self.client
                .from("journal_entries")
                .insert(dto)
                .select()
                .execute()
                .value
        }

        guard let createdDTO = response.first, let created = createdDTO.toDomain() else {
            throw NSError(domain: "JournalService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse created entry"])
        }

        // Trigger embedding generation (fire-and-forget)
        Task {
            do {
                try await ChatService.shared.triggerEmbedding(entryId: created.id)
            } catch {
                                AppLogger.log("⚠️ [JournalService] Failed to trigger embedding: \(error)")
            }
        }

        return created
    }

    /// Updates an existing journal entry.
    func updateEntry(_ entry: JournalEntry) async throws {
        guard let userId = client.auth.currentUser?.id else {
            throw NSError(domain: "JournalService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let dto = JournalEntryDTO(from: entry)
        _ = try await withRetry {
            try await self.client
                .from("journal_entries")
                .update(dto)
                .eq("id", value: entry.id)
                .eq("user_id", value: userId)
                .execute()
        }

        // Trigger embedding regeneration (fire-and-forget)
        Task {
            do {
                try await ChatService.shared.triggerEmbedding(entryId: entry.id)
            } catch {
                                AppLogger.log("⚠️ [JournalService] Failed to trigger embedding: \(error)")
            }
        }
    }

    struct SoftDeleteUpdate: Encodable {
        let is_deleted: Bool
        let deleted_at: String // Use String for ISO date
    }

    /// Soft deletes a journal entry by setting is_deleted = true.
    func deleteEntry(id: UUID) async throws {
        guard let userId = client.auth.currentUser?.id else {
            throw NSError(domain: "JournalService", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        // Formatter for deleted_at
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = formatter.string(from: Date())

        let updatePayload = SoftDeleteUpdate(is_deleted: true, deleted_at: dateString)

        _ = try await withRetry {
            try await self.client
                .from("journal_entries")
                .update(updatePayload)
                .eq("id", value: id)
                .eq("user_id", value: userId)
                .execute()
        }

        // Also delete local encrypted content
        LocalJournalStorage.shared.deleteEncrypted(entryId: id)
    }

    // MARK: - Local-First Helpers (spec-007)

    /// Queues an entry for later sync (offline write, or a transient sync
    /// failure), encrypting the title with the same PIN/path as content.
    func queuePendingSync(entryId: UUID, opType: PendingSyncOperation.OpType, title: String, withPIN pin: String) {
        guard let encryptedTitle = encryptionService.encrypt(title, withPIN: pin) else {
            AppLogger.log("⚠️ [JournalService] Failed to encrypt title for pending sync: \(entryId)")
            return
        }
        LocalJournalStorage.shared.enqueuePendingSync(
            PendingSyncOperation(entryId: entryId, opType: opType, timestamp: Date(), encryptedTitle: encryptedTitle)
        )
    }

    // MARK: - Local-Only Storage (no accounts, spec 023)

    /// Everything needed to fully reconstruct an entry from local storage
    /// alone. `saveEncryptedLocally`'s content-only payload was originally
    /// just a cache — title/dates lived on the server row. With no server
    /// at all, this is now the sole persistence format for an entry: title
    /// and dates round-trip inside the same encrypted blob as the content.
    private struct LocalEntryEnvelope: Codable {
        let title: String
        let content: String
        let createdAt: Date
        let updatedAt: Date
    }

    /// Saves an entry's complete data (title, content, dates) to local
    /// encrypted storage. This is the only place an entry is persisted now
    /// — there is no server round trip to fall back on.
    @discardableResult
    func saveEntryLocally(
        entryId: UUID,
        title: String,
        content: String,
        createdAt: Date,
        updatedAt: Date,
        withPIN pin: String
    ) -> Bool {
        let envelope = LocalEntryEnvelope(title: title, content: content, createdAt: createdAt, updatedAt: updatedAt)
        guard let json = try? JSONEncoder().encode(envelope),
              let jsonString = String(data: json, encoding: .utf8),
              let encrypted = encryptionService.encrypt(jsonString, withPIN: pin) else {
            AppLogger.log("⚠️ [JournalService] Failed to encrypt entry for local storage: \(entryId)")
            return false
        }
        do {
            try LocalJournalStorage.shared.saveEncrypted(entryId: entryId, encryptedData: encrypted)
            return true
        } catch {
            AppLogger.log("⚠️ [JournalService] Failed to save entry locally: \(error)")
            return false
        }
    }

    /// Loads and decrypts every entry stored locally — the sole source of
    /// truth for the journal now that there's no account/server.
    ///
    /// Handles two on-disk formats:
    /// - Envelope (current): the decrypted string is `LocalEntryEnvelope` JSON.
    /// - Legacy (pre-local-only builds): the decrypted string is the raw entry
    ///   content — title/dates lived on the server row or in the pending-sync
    ///   queue, never in this file. Legacy entries are recovered best-effort
    ///   and migrated to envelope format on first read, so the fallback only
    ///   ever runs once per entry.
    func loadAllEntriesLocally(withPIN pin: String) -> [Entry] {
        // Pending-sync ops are the only local record of a legacy entry's
        // title (encrypted) and creation time. Fetch once, not per entry.
        let pendingOps = Dictionary(
            uniqueKeysWithValues: LocalJournalStorage.shared.allPendingSyncOperations().map { ($0.entryId, $0) }
        )

        return LocalJournalStorage.shared.allStoredEntryIds().compactMap { id -> Entry? in
            guard let data = LocalJournalStorage.shared.loadEncrypted(entryId: id),
                  let decrypted = encryptionService.decrypt(data, withPIN: pin) else {
                return nil
            }

            if let json = decrypted.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(LocalEntryEnvelope.self, from: json) {
                return Entry(
                    id: id,
                    title: envelope.title,
                    text: envelope.content,
                    createdAt: envelope.createdAt,
                    updatedAt: envelope.updatedAt,
                    syncStatus: .synced
                )
            }

            // Legacy format: `decrypted` is the raw content itself.
            let pendingOp = pendingOps[id]
            let title = pendingOp.flatMap { encryptionService.decrypt($0.encryptedTitle, withPIN: pin) }
                ?? Self.fallbackTitle(fromContent: decrypted)
            let timestamp = pendingOp?.timestamp
                ?? LocalJournalStorage.shared.modificationDate(entryId: id)
                ?? Date()

            // Migrate to envelope format so this path never runs again for
            // this entry, then drop the queue file — it existed only to
            // retry a server sync that no longer exists.
            saveEntryLocally(entryId: id, title: title, content: decrypted,
                             createdAt: timestamp, updatedAt: timestamp, withPIN: pin)
            LocalJournalStorage.shared.dequeuePendingSync(entryId: id)
            AppLogger.log("📁 [JournalService] Migrated legacy-format entry to envelope: \(id)")

            return Entry(
                id: id, title: title, text: decrypted,
                createdAt: timestamp, updatedAt: timestamp, syncStatus: .synced
            )
        }
    }

    /// Best-effort title for a legacy entry with no recoverable title: its
    /// first non-empty line, truncated, or "Untitled".
    private static func fallbackTitle(fromContent content: String) -> String {
        let firstLine = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !firstLine.isEmpty else { return "Untitled" }
        return firstLine.count > 50 ? String(firstLine.prefix(50)) + "…" : firstLine
    }

}

// MARK: - DTO
// Private Data Transfer Object to handle string-based dates from Supabase
private struct JournalEntryDTO: Codable {
    let id: UUID
    let user_id: UUID
    let title: String
    let content: String
    let word_count: Int?
    let sentiment_score: Double?
    let is_deleted: Bool
    let deleted_at: String?
    let content_hash: String?
    let created_at: String
    let updated_at: String
    
    // Mapping from Domain to DTO
    init(from domain: JournalEntry) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        self.id = domain.id
        self.user_id = domain.userId
        self.title = domain.title
        self.content = domain.content
        self.word_count = domain.wordCount
        self.sentiment_score = domain.sentimentScore
        self.is_deleted = domain.isDeleted
        self.deleted_at = domain.deletedAt.map { formatter.string(from: $0) }
        self.content_hash = domain.contentHash
        self.created_at = formatter.string(from: domain.createdAt)
        self.updated_at = formatter.string(from: domain.updatedAt)
    }
    
    // Mapping from DTO to Domain
    func toDomain() -> JournalEntry? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Try parsing with fractional seconds first, fallback to standard if needed
        guard let created = formatter.date(from: created_at),
              let updated = formatter.date(from: updated_at) else {
            // Fallback for dates without fractional seconds (rare in Postgres but possible)
            let simpleFormatter = ISO8601DateFormatter()
            if let simpleCreated = simpleFormatter.date(from: created_at),
               let simpleUpdated = simpleFormatter.date(from: updated_at) {
                return JournalEntry(
                    id: id,
                    userId: user_id,
                    title: title,
                    content: content,
                    wordCount: word_count,
                    sentimentScore: sentiment_score,
                    isDeleted: is_deleted,
                    deletedAt: deleted_at.flatMap { simpleFormatter.date(from: $0) },
                    contentHash: content_hash,
                    createdAt: simpleCreated,
                    updatedAt: simpleUpdated
                )
            }
            return nil
        }
        
        return JournalEntry(
            id: id,
            userId: user_id,
            title: title,
            content: content,
            wordCount: word_count,
            sentimentScore: sentiment_score,
            isDeleted: is_deleted,
            deletedAt: deleted_at.flatMap { formatter.date(from: $0) },
            contentHash: content_hash,
            createdAt: created,
            updatedAt: updated
        )
    }
}
