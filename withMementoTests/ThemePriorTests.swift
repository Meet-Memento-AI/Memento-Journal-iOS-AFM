import XCTest
@testable import withMemento

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
        let created = Date().addingTimeInterval(-86_400)
        let workplace = Entry(
            title: "marathon training",
            text: "long marathon run this morning, legs sore after the office loop",
            createdAt: created
        )
        let friends = Entry(
            title: "marathon training",
            text: "long marathon run this morning, legs sore after running with friends",
            createdAt: created
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

    /// Every starter the app can show, from every source — not just the two
    /// constants.
    ///
    /// The previous version of this test checked only `previewSamples +
    /// fallbackStarters`. But `rotate` takes **at most one** themed starter and
    /// fills the other two from `AISuggestionPrompts.json`, so most of what a
    /// person actually sees was never covered. That pool still contained
    /// "How has my mood shifted over the past two weeks?" — the exact string
    /// this test forbade — plus "Suggest ways to improve my morning routine"
    /// and "Identify any negative thought patterns I should address", which
    /// spec 019 R6 obliged this surface to remove. The test stayed green and the
    /// copy shipped.
    func test_everyStarterSource_isAdviceFree() {
        for prompt in Self.allStarterPrompts {
            let lower = prompt.lowercased()
            for stem in Self.adviceStems {
                XCTAssertFalse(lower.contains(stem),
                               "\(stem.debugDescription) in starter: \(prompt)")
            }
        }
    }

    /// Starters open a conversation, so they read as something the person says.
    /// An archive command ("Identify any unresolved conflicts I've mentioned")
    /// answers with nothing on an empty journal — which is exactly who is
    /// looking at the empty state.
    func test_starters_readAsSomethingThePersonSays() {
        for prompt in Self.allStarterPrompts {
            let lower = prompt.lowercased()
            for command in ["find ", "identify ", "summarize ", "analyze ", "explore "] {
                XCTAssertFalse(lower.hasPrefix(command),
                               "starter is an archive command, not an opening line: \(prompt)")
            }
        }
    }

    /// The union of every path that can put text on a card.
    static var allStarterPrompts: [String] {
        let bundled = ChatSuggestion.previewSamples + ChatSuggestion.fallbackStarters
        let themed = ThemeAwareChatStarters.starters(
            themeIds: ["stress", "goals", "sleep"], limit: 12
        )
        return (bundled + themed).map(\.label) + ThemeAwareChatStarters.genericPool
    }

    /// Mirrors `ProfileRefreshCoordinator.containsForbiddenPhrase`, whose own
    /// comment says these stems are "used on starters" — they were not, until
    /// now. `scripts/ci/lint_forbidden_phrases.py`, which spec 044 R3 names as
    /// the enforcement for exactly this, checks only absolute-privacy claims
    /// and carries no advice stems at all.
    static let adviceStems = [
        "you should", "i should", "actionable plan", "suggest ways",
        "help me identify", "as your therapist", "coping protocol",
        "mood shifted", "you always", "you never"
    ]

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
