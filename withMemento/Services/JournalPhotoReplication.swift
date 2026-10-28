//
//  JournalPhotoReplication.swift
//  withMemento
//
//  Replicates journal cover JPEGs through SwiftData + CloudKit while keeping
//  the legacy EncryptedPhotos cache for fast local decrypt on the same device.
//

import Foundation
import SwiftData

enum JournalPhotoReplication {
    static var migrationFlagKey: String { "memento_journal_photo_cloud_migration_v1" }

    static var hasCompletedBulkMigration: Bool {
        UserDefaults.standard.bool(forKey: migrationFlagKey)
    }

    static func markBulkMigrationComplete() {
        UserDefaults.standard.set(true, forKey: migrationFlagKey)
    }

    static func clearMigrationFlagForTests() {
        UserDefaults.standard.removeObject(forKey: migrationFlagKey)
    }

    // MARK: - Mirrored cover bytes

    /// Writes the CloudKit-mirrored cover and ensures a photo attachment exists.
    static func persistMirroredCover(
        jpeg: Data,
        entryId: UUID,
        container: ModelContainer? = nil
    ) {
        guard !jpeg.isEmpty else { return }
        let context = MementoDataStore.context(container: container)
        guard let row = existingEntry(id: entryId, context: context) else { return }
        let attachment = photoAttachment(on: row, context: context)
        attachment.coverJPEGData = jpeg
        attachment.fileAssetID = entryId.uuidString
        try? context.save()
    }

    static func clearMirroredCover(entryId: UUID, container: ModelContainer? = nil) {
        let context = MementoDataStore.context(container: container)
        guard let row = existingEntry(id: entryId, context: context) else { return }
        for attachment in row.attachments ?? [] {
            context.delete(attachment)
        }
        row.attachments = []
        try? context.save()
    }

    static func mirroredCoverJPEG(entryId: UUID, container: ModelContainer? = nil) -> Data? {
        let context = MementoDataStore.context(container: container)
        guard let row = existingEntry(id: entryId, context: context) else { return nil }
        guard let data = photoAttachment(on: row, context: context).coverJPEGData, !data.isEmpty else {
            return nil
        }
        return data
    }

    /// Local encrypted cache first, then the CloudKit-mirrored asset.
    static func loadCoverJPEGBytes(
        entryId: UUID,
        encryption: EncryptionService = JournalService.shared.encryptionService,
        container: ModelContainer? = nil
    ) -> Data? {
        if let encrypted = PhotoStorage.shared.loadEncrypted(entryId: entryId),
           let local = encryption.decryptData(encrypted) {
            return local
        }
        if let cloud = mirroredCoverJPEG(entryId: entryId, container: container) {
            cacheLocallyIfPossible(jpeg: cloud, entryId: entryId, encryption: encryption)
            return cloud
        }
        return nil
    }

    // MARK: - One-time upgrade migration

    /// Uploads cover bytes from legacy `EncryptedPhotos/` into SwiftData for
    /// entries that already have a photo attachment but no mirrored asset yet.
    static func migrateLocalEncryptedPhotosIfNeeded(
        encryption: EncryptionService = JournalService.shared.encryptionService,
        container: ModelContainer? = nil
    ) {
        guard !hasCompletedBulkMigration else { return }
        let context = MementoDataStore.context(container: container)
        let rows = (try? context.fetch(FetchDescriptor<StoredEntry>())) ?? []
        var didChange = false
        for row in rows {
            let entryId = row.id
            guard !(row.attachments ?? []).isEmpty else { continue }
            guard PhotoStorage.shared.hasEncrypted(entryId: entryId) else { continue }
            let attachment = photoAttachment(on: row, context: context)
            if let existing = attachment.coverJPEGData, !existing.isEmpty { continue }
            guard let encrypted = PhotoStorage.shared.loadEncrypted(entryId: entryId),
                  let jpeg = encryption.decryptData(encrypted),
                  !jpeg.isEmpty else { continue }
            attachment.coverJPEGData = jpeg
            attachment.fileAssetID = entryId.uuidString
            didChange = true
        }
        if didChange {
            try? context.save()
        }
        markBulkMigrationComplete()
    }

    // MARK: - Integrity

    /// Clears photo metadata when neither the local cache nor mirrored bytes exist.
    @discardableResult
    static func reconcileMissingCover(entryId: UUID, container: ModelContainer? = nil) -> Bool {
        if PhotoStorage.shared.hasEncrypted(entryId: entryId) { return false }
        if mirroredCoverJPEG(entryId: entryId, container: container) != nil { return false }
        clearMirroredCover(entryId: entryId, container: container)
        return true
    }

    static func reconcilePhantomPhotos(container: ModelContainer? = nil) -> Set<UUID> {
        let context = MementoDataStore.context(container: container)
        let rows = (try? context.fetch(FetchDescriptor<StoredEntry>())) ?? []
        var cleared: Set<UUID> = []
        for row in rows where !(row.attachments ?? []).isEmpty {
            if reconcileMissingCover(entryId: row.id, container: container) {
                cleared.insert(row.id)
            }
        }
        if !cleared.isEmpty {
            try? context.save()
        }
        return cleared
    }

    // MARK: - Private

    private static func cacheLocallyIfPossible(
        jpeg: Data,
        entryId: UUID,
        encryption: EncryptionService
    ) {
        guard !PhotoStorage.shared.hasEncrypted(entryId: entryId),
              let encrypted = encryption.encryptData(jpeg) else { return }
        try? PhotoStorage.shared.saveEncrypted(entryId: entryId, encryptedData: encrypted)
    }

    @discardableResult
    private static func photoAttachment(on row: StoredEntry, context: ModelContext) -> StoredAttachment {
        if let existing = (row.attachments ?? []).first(where: { $0.kind == "photo" }) {
            return existing
        }
        let attachment = StoredAttachment()
        attachment.kind = "photo"
        attachment.fileAssetID = row.id.uuidString
        attachment.entry = row
        context.insert(attachment)
        if row.attachments == nil { row.attachments = [] }
        row.attachments?.append(attachment)
        return attachment
    }

    private static func existingEntry(id: UUID, context: ModelContext) -> StoredEntry? {
        var descriptor = FetchDescriptor<StoredEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
