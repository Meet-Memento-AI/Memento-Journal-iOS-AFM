//
//  SampleContentService.swift
//  MeetMemento
//
//  Loads (and removes) a bundled set of sample journal entries.
//
//  Why this exists: Memento reflects on what you have written, so a fresh
//  install has nothing for Weekly, Patterns, or Ask to work with. That is a
//  poor first impression for a real user and an outright Guideline 2.1 risk for
//  App Review — over 40% of unresolved review issues are app completeness, and a
//  reviewer opens the app cold, in a quiet room, with an empty journal.
//
//  The entries are fictional and clearly labelled. Loading is idempotent and
//  fully reversible: entry ids are derived deterministically from the sample id,
//  so re-loading cannot duplicate, and removal deletes exactly what was added
//  and nothing the user wrote.
//
//  Source of the content is `MeetMemento/Resources/SampleEntries.json`, a
//  product asset generated from `Fixtures/corpus/`. It is deliberately a copy
//  rather than a shared file: the corpus is a retrieval-evaluation fixture with
//  a CI validator and gold set, and coupling the two would mean a change made
//  for demo polish could silently move an eval baseline.
//

import CryptoKit
import Foundation

@MainActor
final class SampleContentService: ObservableObject {
    static let shared = SampleContentService()

    private let seededIdsKey = "memento_sample_entry_ids"

    private struct SampleFile: Decodable {
        struct SampleEntry: Decodable {
            let id: String
            let createdAt: Date
            let title: String
            let content: String
        }
        let entries: [SampleEntry]
    }

    /// Published so Settings re-renders when the sample set is added or removed.
    @Published private(set) var loadedCount: Int = 0

    private init() {
        loadedCount = seededIds.count
    }

    /// Ids of entries this service created, so removal never touches the user's
    /// own writing even if a sample entry was later edited.
    private var seededIds: [UUID] {
        get {
            (UserDefaults.standard.array(forKey: seededIdsKey) as? [String] ?? [])
                .compactMap(UUID.init(uuidString:))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: seededIdsKey)
            loadedCount = newValue.count
        }
    }

    var isLoaded: Bool { loadedCount > 0 }

    /// A stable UUID for a sample id, so loading twice overwrites rather than
    /// duplicates and removal can find every entry it created.
    private func entryId(for sampleId: String) -> UUID {
        let digest = SHA256.hash(data: Data(sampleId.utf8))
        var bytes = Array(digest.prefix(16))
        // Stamp RFC 4122 version 4 / variant bits so this is a well-formed UUID.
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    private func decodeBundledSamples() -> [SampleFile.SampleEntry] {
        guard let url = Bundle.main.url(forResource: "SampleEntries", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            AppLogger.log("⚠️ [SampleContent] SampleEntries.json is missing from the bundle")
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(SampleFile.self, from: data).entries
        } catch {
            AppLogger.log("⚠️ [SampleContent] Failed to decode SampleEntries.json: \(error)")
            return []
        }
    }

    /// Writes the bundled samples to local encrypted storage.
    /// - Returns: how many entries are now present.
    @discardableResult
    func load() -> Int {
        let samples = decodeBundledSamples()
        guard !samples.isEmpty else { return 0 }

        var written: [UUID] = []
        for sample in samples {
            let id = entryId(for: sample.id)
            let saved = JournalService.shared.saveEntryLocally(
                entryId: id,
                title: sample.title,
                content: sample.content,
                createdAt: sample.createdAt,
                updatedAt: sample.createdAt
            )
            if saved { written.append(id) }
        }

        seededIds = Array(Set(seededIds).union(written)).sorted { $0.uuidString < $1.uuidString }
        JournalService.shared.invalidateEntriesCache()
        AppLogger.log("📚 [SampleContent] Loaded \(written.count) sample entries")
        return written.count
    }

    /// Deletes exactly the entries `load()` created.
    func remove() {
        let ids = seededIds
        for id in ids {
            LocalJournalStorage.shared.deleteEncrypted(entryId: id)
        }
        seededIds = []
        JournalService.shared.invalidateEntriesCache()
        AppLogger.log("🗑️ [SampleContent] Removed \(ids.count) sample entries")
    }
}
