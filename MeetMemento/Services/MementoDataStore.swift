//
//  MementoDataStore.swift
//  MeetMemento
//
//  Spec 040: SwiftData CRUD for mirrored journal, chat, reflections, profile.
//  The device is the system of record; CloudKit only replicates.
//

import Foundation
import SwiftData

enum MementoDataStore {
    static var importFlagKey: String { "memento_imported_to_swiftdata" }

    static var hasCompletedLegacyImport: Bool {
        UserDefaults.standard.bool(forKey: importFlagKey)
    }

    static func markLegacyImportComplete() {
        UserDefaults.standard.set(true, forKey: importFlagKey)
    }

    static func clearImportFlag() {
        UserDefaults.standard.removeObject(forKey: importFlagKey)
    }

    static func context(container: ModelContainer? = nil) -> ModelContext {
        ModelContext(container ?? JournalContainer.make())
    }

    // MARK: - Entries

    static func upsertEntry(
        id: UUID,
        title: String,
        transcript: String,
        createdAt: Date,
        updatedAt: Date,
        hasPhoto: Bool,
        container: ModelContainer? = nil
    ) {
        let context = context(container: container)
        let row = existingEntry(id: id, context: context) ?? {
            let created = StoredEntry()
            created.id = id
            context.insert(created)
            return created
        }()
        row.title = title
        row.transcript = transcript
        row.createdAt = createdAt
        row.updatedAt = updatedAt
        if hasPhoto {
            if row.attachments?.isEmpty ?? true {
                let attachment = StoredAttachment()
                attachment.kind = "photo"
                attachment.fileAssetID = id.uuidString
                attachment.entry = row
                context.insert(attachment)
            }
        } else {
            for attachment in row.attachments ?? [] {
                context.delete(attachment)
            }
            row.attachments = []
        }
        try? context.save()
    }

    static func allEntries(container: ModelContainer? = nil) -> [Entry] {
        let context = context(container: container)
        let descriptor = FetchDescriptor<StoredEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map { row in
            Entry(
                id: row.id,
                title: row.title,
                text: row.transcript,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt,
                hasPhoto: !(row.attachments ?? []).isEmpty
            )
        }
    }

    static func entry(id: UUID, container: ModelContainer? = nil) -> Entry? {
        allEntries(container: container).first { $0.id == id }
    }

    static func deleteEntry(id: UUID, container: ModelContainer? = nil) {
        let context = context(container: container)
        if let row = existingEntry(id: id, context: context) {
            context.delete(row)
            try? context.save()
        }
    }

    static func entryCount(container: ModelContainer? = nil) -> Int {
        let context = context(container: container)
        return (try? context.fetchCount(FetchDescriptor<StoredEntry>())) ?? 0
    }

    private static func existingEntry(id: UUID, context: ModelContext) -> StoredEntry? {
        var descriptor = FetchDescriptor<StoredEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Conversations

    static func upsertConversation(
        id: UUID,
        title: String,
        at date: Date = Date(),
        container: ModelContainer? = nil
    ) {
        let context = context(container: container)
        let row = existingConversation(id: id, context: context) ?? {
            let created = StoredConversation()
            created.id = id
            created.createdAt = date
            context.insert(created)
            return created
        }()
        if row.title.isEmpty { row.title = title }
        row.updatedAt = date
        try? context.save()
    }

    static func appendTurn(
        conversationId: UUID,
        role: String,
        text: String,
        createdAt: Date = Date(),
        zoneRaw: String = "z0Device",
        wasDegraded: Bool = false,
        promptVersion: String = "",
        container: ModelContainer? = nil
    ) {
        let context = context(container: container)
        let conversation = existingConversation(id: conversationId, context: context) ?? {
            let created = StoredConversation()
            created.id = conversationId
            created.createdAt = createdAt
            created.updatedAt = createdAt
            context.insert(created)
            return created
        }()
        conversation.updatedAt = createdAt
        let turn = StoredTurn()
        turn.roleRaw = role
        turn.text = text
        turn.createdAt = createdAt
        turn.zoneRaw = zoneRaw
        turn.wasDegraded = wasDegraded
        turn.promptVersion = promptVersion
        turn.conversation = conversation
        context.insert(turn)
        try? context.save()
    }

    static func conversations(container: ModelContainer? = nil) -> [ChatSession] {
        let context = context(container: container)
        let descriptor = FetchDescriptor<StoredConversation>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.map {
            ChatSession(id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
        }
    }

    static func turns(conversationId: UUID, container: ModelContainer? = nil) -> [ChatMessageDTO] {
        let context = context(container: container)
        guard let conversation = existingConversation(id: conversationId, context: context) else {
            return []
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (conversation.turns ?? [])
            .sorted { $0.createdAt < $1.createdAt }
            .map {
                ChatMessageDTO(
                    id: $0.id,
                    role: $0.roleRaw,
                    content: $0.text,
                    createdAt: formatter.string(from: $0.createdAt)
                )
            }
    }

    static func deleteConversation(id: UUID, container: ModelContainer? = nil) {
        let context = context(container: container)
        if let row = existingConversation(id: id, context: context) {
            context.delete(row)
            try? context.save()
        }
    }

    static func deleteAllConversations(container: ModelContainer? = nil) {
        let context = context(container: container)
        let rows = (try? context.fetch(FetchDescriptor<StoredConversation>())) ?? []
        for row in rows { context.delete(row) }
        try? context.save()
    }

    private static func existingConversation(id: UUID, context: ModelContext) -> StoredConversation? {
        var descriptor = FetchDescriptor<StoredConversation>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Reflections

    static func upsertWeeklyReflection(body: String, weekStart: Date, container: ModelContainer? = nil) {
        let context = context(container: container)
        let existing = (try? context.fetch(FetchDescriptor<StoredReflection>())) ?? []
        let row = existing.first { $0.kind == .weekly } ?? {
            let created = StoredReflection()
            created.kind = .weekly
            context.insert(created)
            return created
        }()
        row.body = body
        row.createdAt = weekStart
        row.zoneRaw = "z0Device"
        try? context.save()
    }

    static func deleteAllReflections(container: ModelContainer? = nil) {
        let context = context(container: container)
        let rows = (try? context.fetch(FetchDescriptor<StoredReflection>())) ?? []
        for row in rows { context.delete(row) }
        try? context.save()
    }

    // MARK: - Profile

    static func upsertProfile(
        firstName: String,
        lastName: String,
        personalizationText: String,
        experience: ExperienceProfile?,
        aiEnabled: Bool,
        processOnDeviceOnly: Bool,
        container: ModelContainer? = nil
    ) {
        let context = context(container: container)
        let row = (try? context.fetch(FetchDescriptor<StoredProfile>()))?.first ?? {
            let created = StoredProfile()
            context.insert(created)
            return created
        }()
        row.firstName = firstName
        row.lastName = lastName
        row.personalizationText = personalizationText
        row.experienceJSON = experience.flatMap { try? JSONEncoder().encode($0) }
        row.aiEnabled = aiEnabled
        row.processOnDeviceOnly = processOnDeviceOnly
        row.updatedAt = Date()
        try? context.save()
    }

    static func loadProfile(container: ModelContainer? = nil) -> StoredProfile? {
        let context = context(container: container)
        return try? context.fetch(FetchDescriptor<StoredProfile>()).first
    }

    static func deleteAllProfiles(container: ModelContainer? = nil) {
        let context = context(container: container)
        let rows = (try? context.fetch(FetchDescriptor<StoredProfile>())) ?? []
        for row in rows { context.delete(row) }
        try? context.save()
    }
}
