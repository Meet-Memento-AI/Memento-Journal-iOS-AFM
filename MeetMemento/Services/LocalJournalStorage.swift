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

    /// Directory for encrypted journal files
    private var encryptedStorageURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storageURL = documentsURL.appendingPathComponent("EncryptedJournals", isDirectory: true)

        if !fileManager.fileExists(atPath: storageURL.path) {
            do {
                try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
            } catch {
                AppLogger.log("⚠️ [LocalJournalStorage] Failed to create storage directory: \(error)")
            }
        }

        return storageURL
    }

    /// Legacy pending-sync directory from pre–on-device-only builds. Cleared on
    /// wipe; not written to anymore.
    private var legacyPendingSyncURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingSync", isDirectory: true)
    }

    private init() {}

    // MARK: - File Operations

    private func fileURL(for entryId: UUID) -> URL {
        encryptedStorageURL.appendingPathComponent("\(entryId.uuidString).encrypted")
    }

    func saveEncrypted(entryId: UUID, encryptedData: Data) throws {
        let url = fileURL(for: entryId)
        try encryptedData.write(to: url, options: .completeFileProtection)
        AppLogger.log("📁 [LocalJournalStorage] Saved encrypted entry: \(entryId)")
    }

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

    func hasEncrypted(entryId: UUID) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: entryId).path)
    }

    /// The encrypted file's last-modification date — used when migrating
    /// legacy-format entry files whose dates were never stored locally.
    func modificationDate(entryId: UUID) -> Date? {
        let url = fileURL(for: entryId)
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

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

    func clearAll() {
        clearDirectory(at: encryptedStorageURL, label: "encrypted entries")
        clearLegacyPendingSyncDirectory()
    }

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

    // MARK: - Legacy pending-sync cleanup (read-only migration aid)

    /// One-time read of a legacy pending-sync title file, if present from an
    /// older build. Returns nil once the directory is cleared.
    func legacyPendingSyncTitle(for entryId: UUID, decrypt: (Data) -> String?) -> String? {
        let url = legacyPendingSyncURL.appendingPathComponent("\(entryId.uuidString).json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(LegacyPendingSyncRecord.self, from: data) else {
            return nil
        }
        return decrypt(payload.encryptedTitle)
    }

    func removeLegacyPendingSyncRecord(for entryId: UUID) {
        let url = legacyPendingSyncURL.appendingPathComponent("\(entryId.uuidString).json")
        guard fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func clearLegacyPendingSyncDirectory() {
        clearDirectory(at: legacyPendingSyncURL, label: "legacy pending-sync queue")
    }

    private func clearDirectory(at url: URL, label: String) {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for file in contents {
                try fileManager.removeItem(at: file)
            }
            AppLogger.log("🗑️ [LocalJournalStorage] Cleared \(label) (\(contents.count) files)")
        } catch {
            AppLogger.log("⚠️ [LocalJournalStorage] Failed to clear \(label): \(error)")
        }
    }
}

/// Decodes only the fields needed to recover a title from a legacy queue file.
private struct LegacyPendingSyncRecord: Codable {
    let encryptedTitle: Data
}
