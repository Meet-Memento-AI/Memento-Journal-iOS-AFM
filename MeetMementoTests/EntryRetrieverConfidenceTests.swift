import XCTest
@testable import MeetMemento

/// Confidence-bar behavior. `semanticThreshold` is pure math and always
/// deterministic; the retrieve() cases use gibberish/distinct tokens so the
/// keyword path decides even where NLEmbedding is unavailable (CI).
final class EntryRetrieverConfidenceTests: XCTestCase {

    // MARK: - semanticThreshold (pure)

    func test_smallCorpus_usesRaisedAbsoluteFloor() {
        let t = EntryRetriever.semanticThreshold(cosines: [0.9, 0.9], highBar: false)
        XCTAssertEqual(t, RetrieverTuning.default.semanticFloorAbs + 0.05, accuracy: 0.0001)
    }

    func test_flatCorpus_nothingClearsSigma() {
        // Identical cosines: σ = 0 → threshold = max(floor, μ). All values equal
        // μ, so with values below the floor nothing is significant.
        let cosines = Array(repeating: 0.25, count: 10)
        let t = EntryRetriever.semanticThreshold(cosines: cosines, highBar: false)
        XCTAssertEqual(t, RetrieverTuning.default.semanticFloorAbs, accuracy: 0.0001)
        XCTAssertTrue(cosines.allSatisfy { $0 < t })
    }

    func test_outlierClearsThreshold_bulkDoesNot() {
        var cosines = Array(repeating: 0.30, count: 9)
        cosines.append(0.75)
        let t = EntryRetriever.semanticThreshold(cosines: cosines, highBar: false)
        XCTAssertTrue(0.75 >= t, "the outlier should be significant")
        XCTAssertTrue(0.30 < t, "the bulk should not be")
    }

    func test_highBar_isStricter() {
        let cosines = [0.3, 0.35, 0.4, 0.45, 0.5, 0.55]
        let normal = EntryRetriever.semanticThreshold(cosines: cosines, highBar: false)
        let high = EntryRetriever.semanticThreshold(cosines: cosines, highBar: true)
        XCTAssertGreaterThan(high, normal)
    }

    // MARK: - Keyword bar via retrieve()

    private func entry(_ title: String, _ text: String, daysAgo: Double = 1) -> Entry {
        Entry(id: UUID(), title: title, text: text,
              createdAt: Date().addingTimeInterval(-daysAgo * 86_400),
              updatedAt: Date(), syncStatus: .synced)
    }

    /// Gibberish-token corpus: embeddings (if present) can't produce hot
    /// cosines, so the keyword bar decides the signal.
    private func gibberishCorpus() -> [Entry] {
        (0..<6).map { i in
            entry("zorblat \(i)", "flumox vendrik parlune quostam entry number \(i) grebbin marzipol")
        }
    }

    func test_singleSharedWord_isNotASignal() {
        // One body-word overlap scores 1.0 < keywordSignalMin (2.0) → ambient.
        let entries = gibberishCorpus()
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "xudlop wibble quostam"),
            entries: entries
        )
        XCTAssertTrue(result.isAmbient, "a single shared word must not ground the reply")
    }

    func test_titleAndBodyHit_isASignal() {
        // Title hit (1.5) + body hit (1.0) = 2.5 ≥ 2.0 → real match, not ambient.
        var entries = gibberishCorpus()
        entries.append(entry("marathon training", "long marathon run this morning, legs sore"))
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "how did marathon prep go"),
            entries: entries
        )
        XCTAssertFalse(result.isAmbient)
        XCTAssertTrue(result.entries.contains { $0.text.contains("marathon") })
    }

    func test_noMatch_fallsBackToAmbient_cappedForHighBar() {
        let entries = gibberishCorpus()
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "totally unrelated xyzzy words", highBar: true),
            entries: entries
        )
        XCTAssertTrue(result.isAmbient)
        XCTAssertLessThanOrEqual(result.entries.count, RetrieverTuning.default.ambientCapHighBar)
    }

    func test_emptyInputs_returnEmpty() {
        XCTAssertTrue(EntryRetriever.retrieve(RetrievalQuery(currentMessage: "anything"), entries: []).isEmpty)
        XCTAssertTrue(EntryRetriever.retrieve(RetrievalQuery(currentMessage: "   "), entries: gibberishCorpus()).isEmpty)
    }

    func test_ambientContextBlock_usesBackgroundHeader() {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: "nothing in common here at all"),
            entries: gibberishCorpus()
        )
        XCTAssertTrue(result.isAmbient)
        XCTAssertTrue(result.contextBlock.contains("background context"))
    }
}
