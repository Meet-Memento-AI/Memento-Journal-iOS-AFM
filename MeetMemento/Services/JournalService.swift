
import Foundation

/// On-device journal persistence (no accounts, spec 023). Entries live
/// exclusively in encrypted local storage — this service has no backend
/// dependency, so there is no network or API key in the path. The
/// server-backed CRUD that used to live here was dead code from the
/// pre-023 architecture and has been removed.
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
        let ids = LocalJournalStorage.shared.allStoredEntryIds()

        // Return the cached decrypted set when nothing on disk changed. The
        // signature (ids + modification dates) busts automatically on any
        // add/edit/delete, so this avoids re-reading and re-decrypting every
        // entry on every chat message. Decrypted content is PIN-independent, so
        // the cache is valid across PIN changes.
        let signature = Self.cacheSignature(for: ids)
        entriesCacheLock.lock()
        if let cache = entriesCache, cache.signature == signature {
            entriesCacheLock.unlock()
            return cache.entries
        }
        entriesCacheLock.unlock()

        // Pending-sync ops are the only local record of a legacy entry's
        // title (encrypted) and creation time. Fetch once, not per entry.
        let pendingOps = Dictionary(
            uniqueKeysWithValues: LocalJournalStorage.shared.allPendingSyncOperations().map { ($0.entryId, $0) }
        )

        let entries: [Entry] = ids.compactMap { id -> Entry? in
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

        entriesCacheLock.lock()
        entriesCache = (signature, entries)
        entriesCacheLock.unlock()
        return entries
    }

    // MARK: - Decrypted-entries cache

    private let entriesCacheLock = NSLock()
    /// Cache of the decrypted entry set, keyed by a signature of (ids + mtimes).
    private var entriesCache: (signature: String, entries: [Entry])?

    /// Clears the decrypted-entries cache (e.g. on delete-everything / sign-out).
    func invalidateEntriesCache() {
        entriesCacheLock.lock(); entriesCache = nil; entriesCacheLock.unlock()
    }

    private static func cacheSignature(for ids: [UUID]) -> String {
        ids.sorted { $0.uuidString < $1.uuidString }
            .map { id in
                let mtime = LocalJournalStorage.shared.modificationDate(entryId: id)?.timeIntervalSince1970 ?? 0
                return "\(id.uuidString):\(mtime)"
            }
            .joined(separator: "|")
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
