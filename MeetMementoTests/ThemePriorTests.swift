import XCTest
@testable import MeetMemento

/// Spec 044 R3: `themeBoost` reorders signal-clearing hits only.
final class ThemePriorTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThemePriorTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func entry(_ title: String, _ text: String, daysAgo: Double) -> Entry {
        Entry(
            title: title,
            text: text,
            createdAt: Date().addingTimeInterval(-daysAgo * 86_400)
        )
    }

    private func gibberishCorpus() -> [Entry] {
        (0..<6).map { i in
            entry("zorblat \(i)", "flumox vendrik parlune quostam entry number \(i) grebbin marzipol", daysAgo: Double(i + 3))
        }
    }

    /// Same keyword score, same recency, identical stored vectors so cosine
    /// cannot break the tie. Friendship synonym lives only in the second entry.
    func test_themeBoost_reordersTiedSignalHits() {
        let workplace = entry(
            "marathon training",
            "long marathon run this morning, legs sore after the office loop",
            daysAgo: 1
        )
        let friends = entry(
            "marathon training",
            "long marathon run this morning, legs sore after running with friends",
            daysAgo: 1
        )
        let entries = gibberishCorpus() + [workplace, friends]
        let service = seededService(entries: [workplace, friends])
        let query = RetrievalQuery(currentMessage: "how did marathon prep go")

        let without = EntryRetriever.retrieve(query, entries: entries, embeddingService: service)
        let with = EntryRetriever.retrieve(
            query, entries: entries, themeIds: ["friendship"], embeddingService: service
        )

        XCTAssertFalse(without.isAmbient)
        XCTAssertFalse(with.isAmbient)

        let withoutIDs = without.entries.map(\.id)
        let withIDs = with.entries.map(\.id)
        guard let workIdx = withoutIDs.firstIndex(of: workplace.id),
              let friendIdx = withoutIDs.firstIndex(of: friends.id) else {
            return XCTFail("both signal entries must retrieve without themes")
        }
        XCTAssertLessThan(workIdx, friendIdx, "no themes: input order of the tied pair is unchanged")
        XCTAssertEqual(withIDs.first, friends.id, "friendship confirmed: relationships entry ranks first")
        XCTAssertTrue(withIDs.contains(workplace.id), "boost reorders; it must not drop the other hit")
    }

    func test_themeBoost_cannotCreateASignal() {
        var entries = gibberishCorpus()
        entries.append(entry(
            "weekend dinner",
            "Dinner with friends. The connection felt easy all night.",
            daysAgo: 1
        ))
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "how did marathon prep go"),
            entries: entries,
            themeIds: ["friendship"]
        )
        XCTAssertTrue(result.isAmbient, "a theme synonym must not create a topical hit")
    }

    func test_fallbackStarters_areArchivistRecall() {
        let prompts = (ChatSuggestion.previewSamples + ChatSuggestion.fallbackStarters).map(\.prompt)
        for prompt in prompts {
            XCTAssertFalse(prompt.lowercased().contains("actionable plan"))
            XCTAssertFalse(prompt.lowercased().contains("mood shifted"))
        }
        XCTAssertTrue(prompts.contains(where: { $0.contains("sleep lately") }))
    }

    // MARK: - Helpers

    /// Plant identical vectors so cosine cannot break a keyword/recency tie.
    private func seededService(entries: [Entry]) -> EmbeddingService {
        let service = EmbeddingService(directory: directory)
        let vector = Array(repeating: 0.15, count: 16)
        for entry in entries {
            let hash = EmbeddingService.contentHash(title: entry.title, text: entry.text)
            service.storeEntryVector(vector, id: entry.id, contentHash: hash)
            let chunked = PassageChunker.chunk(title: entry.title, text: entry.text)
            for passage in chunked.passages {
                service.storePassageVector(
                    vector, id: entry.id, index: passage.index,
                    textHash: EmbeddingService.stableHash(passage.text),
                    contentHash: hash
                )
            }
        }
        return service
    }
}
