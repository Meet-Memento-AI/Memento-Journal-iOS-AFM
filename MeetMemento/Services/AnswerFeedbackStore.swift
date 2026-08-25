//
//  AnswerFeedbackStore.swift
//  MeetMemento
//
//  On-device JSON store for spec 041 answer feedback. Mirrors LocalChatStore:
//  Application Support, complete file protection, lock + write-behind.
//  Never leaves the device (REQ-PRIV-001).
//

import Foundation

final class AnswerFeedbackStore: @unchecked Sendable {
    static let shared = AnswerFeedbackStore()

    private let lock = NSLock()
    private let fileURL: URL
    private let writeQueue: DispatchQueue
    private var cache: [UUID: AnswerFeedback]?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// `directory` is injectable for tests; defaults to Application Support.
    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MementoFeedback", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("answer-feedback.json")
        writeQueue = DispatchQueue(label: "com.meetmemento.AnswerFeedbackStore.write", qos: .utility)
    }

    func feedback(for messageID: UUID) -> AnswerFeedback? {
        lock.lock(); defer { lock.unlock() }
        return cached()[messageID]
    }

    func feedback(forMessageIDs ids: [UUID]) -> [UUID: AnswerFeedback] {
        lock.lock(); defer { lock.unlock() }
        let all = cached()
        var result: [UUID: AnswerFeedback] = [:]
        for id in ids {
            if let row = all[id] { result[id] = row }
        }
        return result
    }

    /// Rows whose assistant reply text matches, used when a reloaded session
    /// minted new message UUIDs (the live send id is not the persisted DTO id).
    func feedbackMatching(assistantReply: String) -> AnswerFeedback? {
        let needle = assistantReply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        return cached().values.first { $0.assistantReply == needle }
    }

    func allFlagged() -> [AnswerFeedback] {
        lock.lock(); defer { lock.unlock() }
        return cached().values.filter(\.flaggedForReview)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func all() -> [AnswerFeedback] {
        lock.lock(); defer { lock.unlock() }
        return cached().values.sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    func upsert(_ row: AnswerFeedback) -> AnswerFeedback {
        lock.lock(); defer { lock.unlock() }
        var all = cached()
        var stored = row
        stored.updatedAt = Date()
        if let existing = all[row.messageID] {
            stored = AnswerFeedback(
                id: existing.id,
                messageID: row.messageID,
                sessionID: row.sessionID ?? existing.sessionID,
                rating: row.rating,
                flaggedForReview: row.flaggedForReview,
                category: row.category,
                note: row.note,
                source: row.source,
                userPrompt: row.userPrompt.isEmpty ? existing.userPrompt : row.userPrompt,
                assistantReply: row.assistantReply.isEmpty ? existing.assistantReply : row.assistantReply,
                citationEntryIDs: row.citationEntryIDs.isEmpty ? existing.citationEntryIDs : row.citationEntryIDs,
                promptVersion: row.promptVersion ?? existing.promptVersion,
                modelIdentifier: row.modelIdentifier ?? existing.modelIdentifier,
                zone: row.zone ?? existing.zone,
                wasDegraded: row.wasDegraded ?? existing.wasDegraded,
                safetyPresentation: row.safetyPresentation,
                appVersion: row.appVersion.isEmpty ? existing.appVersion : row.appVersion,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
        }
        all[stored.messageID] = stored
        cache = all
        scheduleWrite(all)
        return stored
    }

    func flush() {
        writeQueue.sync {}
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        cache = [:]
        writeQueue.sync { [fileURL] in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Pretty-printed JSON snapshot for Settings export. Nil when empty.
    func exportJSONData() throws -> Data? {
        let rows = all()
        guard !rows.isEmpty else { return nil }
        let exportEncoder = JSONEncoder()
        exportEncoder.dateEncodingStrategy = .iso8601
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try exportEncoder.encode(rows)
    }

    // MARK: - Private

    private func cached() -> [UUID: AnswerFeedback] {
        if let cache { return cache }
        let loaded = loadFromDisk()
        cache = loaded
        return loaded
    }

    private func loadFromDisk() -> [UUID: AnswerFeedback] {
        guard let data = try? Data(contentsOf: fileURL),
              let rows = try? decoder.decode([AnswerFeedback].self, from: data) else {
            return [:]
        }
        var map: [UUID: AnswerFeedback] = [:]
        for row in rows { map[row.messageID] = row }
        return map
    }

    private func scheduleWrite(_ all: [UUID: AnswerFeedback]) {
        let snapshot = Array(all.values)
        let url = fileURL
        let encoder = encoder
        writeQueue.async {
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
