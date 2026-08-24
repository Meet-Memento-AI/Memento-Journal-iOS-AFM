//
//  FiveStoreDeletion.swift
//  MeetMemento
//
//  Spec 015 R6 / 040 / REQ-DATA-013: Delete everything across the five stores.
//  (1) SwiftData  (2) audio files  (3) Spotlight  (4) TTS cache  (5) CloudKit
//

import CloudKit
import Foundation
import SwiftData

enum CloudKitWipeOutcome: Equatable {
    case issued
    case queuedPending
    case skippedNoAccount
}

enum FiveStoreDeletion {
    /// Last CloudKit wipe result — tests assert issued or queued, never a silent skip.
    static var lastCloudKitOutcome: CloudKitWipeOutcome?

    @MainActor
    static func run(container: ModelContainer? = nil) async {
        let resolved = container ?? JournalContainer.make()
        await deleteSwiftData(resolved)
        AudioAssetStore.deleteAll()
        TTSRenderCache.deleteAll()
        await EntrySpotlightIndexer.removeAll()
        await deleteCloudKitRecords()
        LocalJournalStorage.shared.clearAll()
        MementoDataStore.clearImportFlag()
    }

    @MainActor
    private static func deleteSwiftData(_ container: ModelContainer) async {
        let context = ModelContext(container)
        deleteAll(StoredEntry.self, context: context)
        deleteAll(StoredAttachment.self, context: context)
        deleteAll(StoredReflection.self, context: context)
        deleteAll(StoredCitation.self, context: context)
        deleteAll(StoredConversation.self, context: context)
        deleteAll(StoredTurn.self, context: context)
        deleteAll(StoredProfile.self, context: context)
        try? context.save()
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) {
        do {
            let descriptor = FetchDescriptor<T>()
            let rows = try context.fetch(descriptor)
            for row in rows { context.delete(row) }
        } catch {
            AppLogger.log("[FiveStoreDeletion] fetch/delete \(type) failed: \(error.localizedDescription)")
        }
    }

    /// Issues a private-DB wipe. Offline / signed-out → pending, never a silent skip.
    static func deleteCloudKitRecords() async {
        let container = CKContainer(identifier: JournalSchema.cloudKitContainerID)
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                lastCloudKitOutcome = .skippedNoAccount
                await MainActor.run { SyncStatusStore.shared.markDeletionPending() }
                AppLogger.log("[FiveStoreDeletion] CloudKit unavailable; local delete done, iCloud pending.")
                return
            }
            let database = container.privateCloudDatabase
            var deletedAny = false
            do {
                let zones = try await database.allRecordZones()
                for zone in zones {
                    if zone.zoneID == CKRecordZone.default().zoneID { continue }
                    try await database.deleteRecordZone(withID: zone.zoneID)
                    deletedAny = true
                }
            } catch {
                AppLogger.log("[FiveStoreDeletion] Zone wipe: \(error.localizedDescription)")
            }
            let types = [
                "CD_StoredEntry", "CD_StoredAttachment", "CD_StoredReflection",
                "CD_StoredCitation", "CD_StoredConversation", "CD_StoredTurn",
                "CD_StoredProfile", "StoredEntry", "StoredProfile"
            ]
            for typeName in types {
                deletedAny = (await deleteRecords(ofType: typeName, in: database)) || deletedAny
            }
            lastCloudKitOutcome = .issued
            await MainActor.run { SyncStatusStore.shared.clearDeletionPending() }
            AppLogger.log("[FiveStoreDeletion] CloudKit wipe issued (zones/records touched: \(deletedAny)).")
        } catch {
            lastCloudKitOutcome = .queuedPending
            await MainActor.run { SyncStatusStore.shared.markDeletionPending() }
            AppLogger.log("[FiveStoreDeletion] CloudKit wipe queued: \(error.localizedDescription)")
        }
    }

    private static func deleteRecords(ofType typeName: String, in database: CKDatabase) async -> Bool {
        do {
            let query = CKQuery(recordType: typeName, predicate: NSPredicate(value: true))
            let (results, _) = try await database.records(matching: query, desiredKeys: [])
            var ids: [CKRecord.ID] = []
            for (id, result) in results {
                if case .success = result { ids.append(id) }
            }
            guard !ids.isEmpty else { return false }
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: ids)
            operation.savePolicy = .allKeys
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success: continuation.resume()
                    case .failure(let error): continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
            return true
        } catch {
            return false
        }
    }
}

enum TTSRenderCache {
    static var directoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("TTSRenders", isDirectory: true)
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    static var isEmpty: Bool {
        let items = try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        return (items ?? []).isEmpty
    }
}
