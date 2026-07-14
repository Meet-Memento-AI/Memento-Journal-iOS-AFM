
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

    // MARK: - Encrypted Operations (PIN-aware)

    /// Creates a new journal entry with local encryption.
    /// Saves plaintext to Supabase (for recovery) and encrypted content locally.
    /// - Parameters:
    ///   - entry: The journal entry to create
    ///   - pin: The user's PIN for encryption
    /// - Returns: The created entry
    @discardableResult
    func createEntry(_ entry: JournalEntry, withPIN pin: String) async throws -> JournalEntry {
        // 1. Save plaintext to Supabase (for recovery)
        let created = try await createEntry(entry)

        // 2. Encrypt content locally with PIN
        if let encrypted = EncryptionService.shared.encrypt(entry.content, withPIN: pin) {
            do {
                try LocalJournalStorage.shared.saveEncrypted(entryId: created.id, encryptedData: encrypted)
            } catch {
                                AppLogger.log("⚠️ [JournalService] Failed to save encrypted content locally: \(error)")
                // Don't fail the operation - Supabase has the backup
            }
        }

        return created
    }

    /// Updates a journal entry with local encryption.
    /// - Parameters:
    ///   - entry: The journal entry to update
    ///   - pin: The user's PIN for encryption
    func updateEntry(_ entry: JournalEntry, withPIN pin: String) async throws {
        // 1. Update plaintext in Supabase (for recovery)
        try await updateEntry(entry)

        // 2. Re-encrypt content locally with PIN
        if let encrypted = EncryptionService.shared.encrypt(entry.content, withPIN: pin) {
            do {
                try LocalJournalStorage.shared.saveEncrypted(entryId: entry.id, encryptedData: encrypted)
            } catch {
                                AppLogger.log("⚠️ [JournalService] Failed to update encrypted content locally: \(error)")
            }
        }
    }

    /// Fetches entries and decrypts local content where available.
    /// Falls back to Supabase plaintext if local decryption fails.
    /// - Parameter pin: The user's PIN for decryption
    /// - Returns: Array of journal entries with decrypted content
    func fetchEntries(withPIN pin: String) async throws -> [JournalEntry] {
        // Fetch from Supabase
        let entries = try await fetchEntries()

        // Try to decrypt local content for each entry
        return entries.map { entry in
            // Check if we have local encrypted content
            if let encryptedData = LocalJournalStorage.shared.loadEncrypted(entryId: entry.id),
               let decrypted = EncryptionService.shared.decrypt(encryptedData, withPIN: pin) {
                // Use locally decrypted content
                return JournalEntry(
                    id: entry.id,
                    userId: entry.userId,
                    title: entry.title,
                    content: decrypted,
                    wordCount: entry.wordCount,
                    sentimentScore: entry.sentimentScore,
                    isDeleted: entry.isDeleted,
                    deletedAt: entry.deletedAt,
                    contentHash: entry.contentHash,
                    createdAt: entry.createdAt,
                    updatedAt: entry.updatedAt
                )
            }

            // Fall back to Supabase plaintext (recovery mode)
            // Also re-encrypt locally for next time
            if let encrypted = EncryptionService.shared.encrypt(entry.content, withPIN: pin) {
                try? LocalJournalStorage.shared.saveEncrypted(entryId: entry.id, encryptedData: encrypted)
            }

            return entry
        }
    }

    /// Re-encrypts all entries with a new PIN.
    /// Call this when the user changes their PIN.
    /// - Parameter newPIN: The new PIN to use for encryption
    func reEncryptAll(withNewPIN newPIN: String) async throws {
        // Clear old encrypted storage
        LocalJournalStorage.shared.clearAll()

        // Fetch entries from Supabase and re-encrypt
        let entries = try await fetchEntries()
        for entry in entries {
            if let encrypted = EncryptionService.shared.encrypt(entry.content, withPIN: newPIN) {
                try? LocalJournalStorage.shared.saveEncrypted(entryId: entry.id, encryptedData: encrypted)
            }
        }

                AppLogger.log("🔐 [JournalService] Re-encrypted \(entries.count) entries with new PIN")
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
