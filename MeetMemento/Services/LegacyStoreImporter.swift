//
//  LegacyStoreImporter.swift
//  MeetMemento
//
//  Spec 040 R4: one-time import of encrypted journals, LocalChatStore, and
//  LocalProfileStore into SwiftData. Idempotent.
//

import Foundation
import SwiftData

enum LegacyStoreImporter {
    /// Imports legacy file/UserDefaults stores into SwiftData once, then
    /// deletes the file copies. Safe to call on every launch.
    @discardableResult
    static func importIfNeeded(
        encryptionService: EncryptionService = .shared,
        legacyPIN: String? = nil,
        container: ModelContainer? = nil
    ) -> Bool {
        if MementoDataStore.hasCompletedLegacyImport { return false }

        let resolved = container ?? JournalContainer.make()

        importJournals(encryptionService: encryptionService, legacyPIN: legacyPIN, container: resolved)
        importChats(container: resolved)
        importProfile(container: resolved)
        importWeeklyReflection(container: resolved)

        MementoDataStore.markLegacyImportComplete()

        LocalJournalStorage.shared.clearAll()
        LocalChatStore.shared.clear()

        AppLogger.log("[LegacyStoreImporter] Imported local stores into SwiftData")
        return true
    }

    private static func importJournals(
        encryptionService: EncryptionService,
        legacyPIN: String?,
        container: ModelContainer
    ) {
        // Temporary reader that does not recurse into SwiftData.
        let service = JournalService(encryptionService: encryptionService)
        let entries = service.loadLegacyFilesOnly(legacyPIN: legacyPIN)
        for entry in entries {
            MementoDataStore.upsertEntry(
                id: entry.id,
                title: entry.title,
                transcript: entry.text,
                createdAt: entry.createdAt,
                updatedAt: entry.updatedAt,
                hasPhoto: entry.hasPhoto,
                container: container
            )
        }
    }

    private static func importChats(container: ModelContainer) {
        let sessions = LocalChatStore.shared.sessions()
        for session in sessions {
            MementoDataStore.upsertConversation(
                id: session.id,
                title: session.title,
                at: session.updatedAt,
                container: container
            )
            let messages = LocalChatStore.shared.messages(for: session.id)
            for message in messages {
                let created: Date = {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    if let date = formatter.date(from: message.createdAt) { return date }
                    formatter.formatOptions = [.withInternetDateTime]
                    return formatter.date(from: message.createdAt) ?? session.createdAt
                }()
                MementoDataStore.appendTurn(
                    conversationId: session.id,
                    role: message.role,
                    text: message.content,
                    createdAt: created,
                    container: container
                )
            }
        }
    }

    private static func importProfile(container: ModelContainer) {
        let first = UserDefaults.standard.string(forKey: "memento_first_name") ?? ""
        let last = UserDefaults.standard.string(forKey: "memento_last_name") ?? ""
        let profile = LocalProfileStore.experienceProfile
        MementoDataStore.upsertProfile(
            firstName: first,
            lastName: last,
            personalizationText: LocalProfileStore.personalizationText ?? "",
            experience: profile,
            aiEnabled: PreferencesService.shared.aiEnabled,
            processOnDeviceOnly: PreferencesService.shared.processOnDeviceOnly,
            container: container
        )
    }

    private static func importWeeklyReflection(container: ModelContainer) {
        guard let body = WeeklyReflectionStore.latestBody,
              let weekStart = WeeklyReflectionStore.weekStart else { return }
        MementoDataStore.upsertWeeklyReflection(body: body, weekStart: weekStart, container: container)
    }
}
