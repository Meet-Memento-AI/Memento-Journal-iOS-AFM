//
//  LocalJournalStorage.swift
//  MeetMemento
//
//  Stores encrypted journal content on device for local viewing.
//  Each entry is saved as a separate file for efficient access.
//

import Foundation

class LocalJournalStorage {
    static let shared = LocalJournalStorage()

    private let fileManager = FileManager.default

    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Directory for encrypted journal files
    private var encryptedStorageURL: URL {
        let storageURL = documentsURL.appendingPathComponent("EncryptedJournals", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: storageURL.path) {
            do {
                try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
            } catch {
                AppLogger.log("⚠️ [LocalJournalStorage] Failed to create storage directory: \(error)")
            }
        }

        return storageURL
    }

    /// Pre-1.x leftover: a server retry queue that no longer has a server.
    /// Never recreate this directory. `purgeLegacyPendingSyncDirectory()`
    /// deletes it on first access and on delete-everything.
    private var legacyPendingSyncDirectoryURL: URL {
        documentsURL.appendingPathComponent("PendingSync", isDirectory: true)
    }

    private init() {
        purgeLegacyPendingSyncDirectory()
    }

    // MARK: - File Operations

    /// Returns the file URL for a specific entry
    private func fileURL(for entryId: UUID) -> URL {
        encryptedStorageURL.appendingPathComponent("\(entryId.uuidString).encrypted")
    }

    /// Saves encrypted journal content locally
    /// - Parameters:
    ///   - entryId: The journal entry UUID
    ///   - encryptedData: The encrypted content data
    func saveEncrypted(entryId: UUID, encryptedData: Data) throws {
        let url = fileURL(for: entryId)
        try encryptedData.write(to: url, options: .completeFileProtection)
                AppLogger.log("📁 [LocalJournalStorage] Saved encrypted entry: \(entryId)")
    }

    /// Loads encrypted journal content
    /// - Parameter entryId: The journal entry UUID
    /// - Returns: The encrypted data, or nil if not found
    func loadEncrypted(entryId: UUID) -> Data? {
        let url = fileURL(for: entryId)

        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            AppLogger.log("⚠️ [LocalJournalStorage] Failed to load encrypted entry \(entryId): \(error)")
            return nil
        }
    }

    /// Checks if encrypted content exists for an entry
    /// - Parameter entryId: The journal entry UUID
    /// - Returns: True if local encrypted content exists
    func hasEncrypted(entryId: UUID) -> Bool {
        let url = fileURL(for: entryId)
        return fileManager.fileExists(atPath: url.path)
    }

    /// The encrypted file's last-modification date — used as a best-effort
    /// timestamp when migrating legacy-format entries whose dates were never
    /// stored locally (they lived on the old server row).
    func modificationDate(entryId: UUID) -> Date? {
        let url = fileURL(for: entryId)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    /// Deletes encrypted content for a specific entry
    /// - Parameter entryId: The journal entry UUID
    func deleteEncrypted(entryId: UUID) {
        let url = fileURL(for: entryId)

        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
                        AppLogger.log("🗑️ [LocalJournalStorage] Deleted encrypted entry: \(entryId)")
        } catch {
            AppLogger.log("⚠️ [LocalJournalStorage] Failed to delete encrypted entry \(entryId): \(error)")
        }
    }

    /// Clears all encrypted content (called on logout, PIN change, or
    /// delete-everything). Also removes any leftover pre-1.x sync queue.
    func clearAll() {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: encryptedStorageURL,
                includingPropertiesForKeys: nil
            )

            for file in contents {
                try fileManager.removeItem(at: file)
            }

                        AppLogger.log("🗑️ [LocalJournalStorage] Cleared all encrypted entries (\(contents.count) files)")
        } catch {
            AppLogger.log("⚠️ [LocalJournalStorage] Failed to clear all: \(error)")
        }
        purgeLegacyPendingSyncDirectory()
    }

    /// Deletes `Documents/PendingSync` if a previous build left it behind.
    /// There is no server to drain; leftover files would contradict the
    /// on-device-only product. Safe to call repeatedly.
    func purgeLegacyPendingSyncDirectory() {
        let url = legacyPendingSyncDirectoryURL
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            AppLogger.log("🗑️ [LocalJournalStorage] Removed leftover PendingSync directory")
        } catch {
            AppLogger.log("⚠️ [LocalJournalStorage] Failed to remove PendingSync: \(error)")
        }
    }

    /// Returns the count of locally stored encrypted entries
    var storedEntryCount: Int {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: encryptedStorageURL,
                includingPropertiesForKeys: nil
            )
            return contents.filter { $0.pathExtension == "encrypted" }.count
        } catch {
            return 0
        }
    }

    /// Returns all entry IDs that have local encrypted storage
    func allStoredEntryIds() -> [UUID] {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: encryptedStorageURL,
                includingPropertiesForKeys: nil
            )

            return contents.compactMap { url -> UUID? in
                guard url.pathExtension == "encrypted" else { return nil }
                let filename = url.deletingPathExtension().lastPathComponent
                return UUID(uuidString: filename)
            }
        } catch {
            return []
        }
    }

}
