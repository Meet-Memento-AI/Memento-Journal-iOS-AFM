//
//  PhotoStorage.swift
//  MeetMemento
//
//  Stores encrypted journal entry photos on device — one file per entry, keyed
//  by the entry's own UUID. Deliberately mirrors LocalJournalStorage's shape,
//  but lives in its own directory (EncryptedPhotos, not EncryptedJournals) so
//  neither store has to filter the other's files out of its directory listing.
//
//  Photo bytes are NOT inlined into JournalService's LocalEntryEnvelope JSON:
//  that envelope is decrypted for every entry on every list load (it's on the
//  hot path for AI chat context too, not just the journal tab). Keeping photos
//  in a sibling file, decrypted only when a thumbnail is about to render,
//  keeps that "cheap text load, lazy heavy asset" split intact.
//

import Foundation

class PhotoStorage {
    static let shared = PhotoStorage()

    private let fileManager = FileManager.default

    /// Directory for encrypted photo files — separate from EncryptedJournals.
    private var encryptedStorageURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let storageURL = documentsURL.appendingPathComponent("EncryptedPhotos", isDirectory: true)

        if !fileManager.fileExists(atPath: storageURL.path) {
            do {
                try fileManager.createDirectory(at: storageURL, withIntermediateDirectories: true)
            } catch {
                AppLogger.log("⚠️ [PhotoStorage] Failed to create storage directory: \(error)")
            }
        }

        return storageURL
    }

    private init() {}

    private func fileURL(for entryId: UUID) -> URL {
        encryptedStorageURL.appendingPathComponent("\(entryId.uuidString).encrypted")
    }

    /// Saves an entry's encrypted photo, overwriting any existing one — single
    /// photo per entry, so a save always replaces rather than appends.
    ///
    /// `.atomic` because a replace overwrites a file that may still be the
    /// user's only copy of the previous photo: an interrupted non-atomic write
    /// would leave a truncated, undecryptable file rather than cleanly either
    /// the old or the new one.
    func saveEncrypted(entryId: UUID, encryptedData: Data) throws {
        let url = fileURL(for: entryId)
        try encryptedData.write(to: url, options: [.atomic, .completeFileProtection])
        AppLogger.log("📁 [PhotoStorage] Saved encrypted photo: \(entryId)")
    }

    /// Loads an entry's encrypted photo, or nil if it has none.
    func loadEncrypted(entryId: UUID) -> Data? {
        let url = fileURL(for: entryId)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            AppLogger.log("⚠️ [PhotoStorage] Failed to load encrypted photo \(entryId): \(error)")
            return nil
        }
    }

    /// Whether an entry has a stored photo.
    func hasEncrypted(entryId: UUID) -> Bool {
        fileManager.fileExists(atPath: fileURL(for: entryId).path)
    }

    /// Deletes an entry's photo. Safe no-op if it has none.
    func deleteEncrypted(entryId: UUID) {
        let url = fileURL(for: entryId)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            AppLogger.log("🗑️ [PhotoStorage] Deleted encrypted photo: \(entryId)")
        } catch {
            AppLogger.log("⚠️ [PhotoStorage] Failed to delete encrypted photo \(entryId): \(error)")
        }
    }

    /// Clears all stored photos (e.g. Delete Everything).
    func clearAll() {
        do {
            let contents = try fileManager.contentsOfDirectory(at: encryptedStorageURL, includingPropertiesForKeys: nil)
            for file in contents {
                try fileManager.removeItem(at: file)
            }
            AppLogger.log("🗑️ [PhotoStorage] Cleared all encrypted photos (\(contents.count) files)")
        } catch {
            AppLogger.log("⚠️ [PhotoStorage] Failed to clear all: \(error)")
        }
    }
}
