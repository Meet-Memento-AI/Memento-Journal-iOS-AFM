
import Foundation

/// On-device journal persistence (no accounts, spec 023). Entries live
/// exclusively in encrypted local storage.
class JournalService {
    static let shared = JournalService()

    let encryptionService: EncryptionService

    init(encryptionService: EncryptionService = .shared) {
        self.encryptionService = encryptionService
    }

    // MARK: - Local-Only Storage

    private struct LocalEntryEnvelope: Codable {
        let title: String
        let content: String
        let createdAt: Date
        let updatedAt: Date
    }

    @discardableResult
    func saveEntryLocally(
        entryId: UUID,
        title: String,
        content: String,
        createdAt: Date,
        updatedAt: Date
    ) -> Bool {
        let envelope = LocalEntryEnvelope(title: title, content: content, createdAt: createdAt, updatedAt: updatedAt)
        guard let json = try? JSONEncoder().encode(envelope),
              let jsonString = String(data: json, encoding: .utf8),
              let encrypted = encryptionService.encrypt(jsonString) else {
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

    func loadAllEntriesLocally(legacyPIN: String?) -> [Entry] {
        let ids = LocalJournalStorage.shared.allStoredEntryIds()

        let signature = Self.cacheSignature(for: ids)
        entriesCacheLock.lock()
        if let cache = entriesCache, cache.signature == signature {
            entriesCacheLock.unlock()
            return cache.entries
        }
        entriesCacheLock.unlock()

        let entries: [Entry] = ids.compactMap { id -> Entry? in
            guard let data = LocalJournalStorage.shared.loadEncrypted(entryId: id),
                  let read = encryptionService.decryptMigrating(data, legacyPIN: legacyPIN) else {
                return nil
            }
            let decrypted = read.text

            if let json = decrypted.data(using: .utf8),
               let envelope = try? JSONDecoder().decode(LocalEntryEnvelope.self, from: json) {
                if read.needsRewrite {
                    saveEntryLocally(entryId: id, title: envelope.title, content: envelope.content,
                                     createdAt: envelope.createdAt, updatedAt: envelope.updatedAt)
                    AppLogger.log("🔐 [JournalService] Re-encrypted entry under the data key: \(id)")
                }
                return Entry(
                    id: id,
                    title: envelope.title,
                    text: envelope.content,
                    createdAt: envelope.createdAt,
                    updatedAt: envelope.updatedAt
                )
            }

            // Legacy format: decrypted string is raw content.
            let legacyTitle = LocalJournalStorage.shared.legacyPendingSyncTitle(for: id) { encryptedTitle in
                if let pin = legacyPIN, let title = encryptionService.decrypt(encryptedTitle, withPIN: pin) {
                    return title
                }
                return encryptionService.decrypt(encryptedTitle)
            } ?? Self.fallbackTitle(fromContent: decrypted)

            let timestamp = LocalJournalStorage.shared.modificationDate(entryId: id) ?? Date()

            saveEntryLocally(entryId: id, title: legacyTitle, content: decrypted,
                             createdAt: timestamp, updatedAt: timestamp)
            LocalJournalStorage.shared.removeLegacyPendingSyncRecord(for: id)
            AppLogger.log("📁 [JournalService] Migrated legacy-format entry to envelope: \(id)")

            return Entry(
                id: id, title: legacyTitle, text: decrypted,
                createdAt: timestamp, updatedAt: timestamp
            )
        }

        if entries.count == ids.count {
            entriesCacheLock.lock()
            entriesCache = (signature, entries)
            entriesCacheLock.unlock()
        } else {
            AppLogger.log("⚠️ [JournalService] \(ids.count - entries.count)/\(ids.count) entries unreadable with the current key material — not caching")
        }
        return entries
    }

    // MARK: - Decrypted-entries cache

    private let entriesCacheLock = NSLock()
    private var entriesCache: (signature: String, entries: [Entry])?

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
