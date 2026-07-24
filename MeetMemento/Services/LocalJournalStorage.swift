//
//  LocalJournalStorage.swift
//  MeetMemento
//
//  Stores encrypted journal content on device for local viewing.
//  Each entry is saved as a separate file for efficient access.
//

import Foundation

/// A journal write that hasn't been confirmed on the server yet, either
/// because it was made offline or because the sync attempt failed
/// transiently. Tracks only the operation to retry — the actual content
/// lives in the existing encrypted-content store (`saveEncrypted`), so a
/// queued entry goes through the exact same `EncryptionService` path as a
/// synced one; nothing here duplicates plaintext at rest.
struct PendingSyncOperation: Codable {
    enum OpType: String, Codable {
        case create, update, delete
    }

    let entryId: UUID
    let opType: OpType
    let timestamp: Date
    /// Entry title, encrypted with the same session PIN as the content —
    /// titles aren't part of `saveEncrypted`'s payload, but a queued create
    /// has nowhere else to persist its title until the server round-trip
    /// completes, so it gets the same protection here.
    let encryptedTitle: Data
}

class LocalJournalStorage {
    static let shared = LocalJournalStorage()

    private let fileManager = FileManager.default

    /// Directory for encrypted journal files
    private var encryptedStorageURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
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

    /// Directory for the pending-sync queue index (one JSON file per queued op).
    private var pendingSyncStorageURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storageURL = documentsURL.appendingPathComponent("PendingSync", isDirectory: true)

        if !fileManager.fileExists(atPath: storageURL.path) {
            do {
                try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
            } catch {
                AppLogger.log("⚠️ [LocalJournalStorage] Failed to create pending-sync directory: \(error)")
            }
        }

        return storageURL
    }

    private init() {}

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

    /// Clears all encrypted content (called on logout or PIN change)
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

    // MARK: - Pending Sync Queue

    private func pendingSyncFileURL(for entryId: UUID) -> URL {
        pendingSyncStorageURL.appendingPathComponent("\(entryId.uuidString).json")
    }

    /// Queues (or replaces) a pending sync operation for an entry. A later
    /// call for the same `entryId` overwrites the earlier one — e.g. an
    /// offline edit right after an offline create just updates the queued
    /// `create` op's title, it doesn't stack a second op.
    func enqueuePendingSync(_ operation: PendingSyncOperation) {
        do {
            let data = try JSONEncoder().encode(operation)
            try data.write(to: pendingSyncFileURL(for: operation.entryId), options: .completeFileProtection)
            AppLogger.log("📁 [LocalJournalStorage] Queued pending sync (\(operation.opType.rawValue)): \(operation.entryId)")
        } catch {
            AppLogger.log("⚠️ [LocalJournalStorage] Failed to queue pending sync for \(operation.entryId): \(error)")
        }
    }

    /// Removes an entry's queued operation once it has synced successfully.
    func dequeuePendingSync(entryId: UUID) {
        let url = pendingSyncFileURL(for: entryId)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            AppLogger.log("✅ [LocalJournalStorage] Dequeued synced entry: \(entryId)")
        } catch {
            AppLogger.log("⚠️ [LocalJournalStorage] Failed to dequeue \(entryId): \(error)")
        }
    }

    /// True if an entry has an unsynced local write pending.
    func hasPendingSync(entryId: UUID) -> Bool {
        fileManager.fileExists(atPath: pendingSyncFileURL(for: entryId).path)
    }

    /// All queued operations, oldest first, so a drain retries them in the
    /// order they were made.
    func allPendingSyncOperations() -> [PendingSyncOperation] {
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: pendingSyncStorageURL,
                includingPropertiesForKeys: nil
            )
            let operations = contents.compactMap { url -> PendingSyncOperation? in
                guard url.pathExtension == "json",
                      let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(PendingSyncOperation.self, from: data)
            }
            return operations.sorted { $0.timestamp < $1.timestamp }
        } catch {
            return []
        }
    }
}
