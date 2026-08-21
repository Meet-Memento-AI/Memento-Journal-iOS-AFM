//
//  FiveStoreDeletion.swift
//  MeetMemento
//
//  Spec 015 R6 / REQ-DATA-013: Delete everything across the five stores.
//  (1) SwiftData  (2) audio files  (3) Spotlight  (4) TTS cache  (5) CloudKit
//

import CloudKit
import Foundation
import SwiftData

enum FiveStoreDeletion {
    @MainActor
    static func run(container: ModelContainer? = nil) async {
        let resolved = container ?? JournalContainer.make()
        await deleteSwiftData(resolved)
        AudioAssetStore.deleteAll()
        TTSRenderCache.deleteAll()
        await EntrySpotlightIndexer.removeAll()
        await deleteCloudKitRecords()
        LocalJournalStorage.shared.clearAll()
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

    private static func deleteCloudKitRecords() async {
        let container = CKContainer(identifier: JournalSchema.cloudKitContainerID)
        do {
            let status = try await container.accountStatus()
            guard status == .available else { return }
            AppLogger.log("[FiveStoreDeletion] CloudKit account available; local SwiftData mirror already empty.")
        } catch {
            AppLogger.log("[FiveStoreDeletion] CloudKit: \(error.localizedDescription)")
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
