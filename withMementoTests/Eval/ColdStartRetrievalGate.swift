import XCTest
@testable import withMemento

/// Retrieval on a journal that is three entries old.
///
/// `RetrievalGate` and `RetrievalRecallDiag` both require ≥ 250 entries, so the
/// size a new install actually has was never measured — which is where the
/// "I don't see anything" replies were reported. This gate closes that hole and,
/// unlike the persona gates, runs on every merge: retrieval is model-free and
/// the fixture is eight entries.
///
/// Two properties are gated, and they pull against each other:
///
///   - **Recall** — a question whose words are in an entry must ground, or the
///     reply falls to ambient and the person is told nothing matches.
///   - **Abstention** — a question about something the journal never mentions
///     must *not* ground, however warmly the embeddings score it. This is the
///     property the small-corpus neighbour matching could break, so it is
///     asserted at every corpus size.
final class ColdStartRetrievalGate: XCTestCase {

    private static let sizes = [3, 5, 8]

    /// Categories whose recall depends on `NLEmbedding` being present: the
    /// neighbour test is what carries them, and CI machines without the word
    /// embedding cannot run it. Keyword-decidable categories are asserted
    /// unconditionally.
    private static let embeddingDependent: Set<String> = ["vocabulary"]

    /// Documented gap, not a failure: "exercising" and "running" are synonyms,
    /// not inflections, and nothing short of grounding on sentence-level
    /// similarity would connect them. Reported so a future change that does fix
    /// it is visible.
    private static let knownGaps: Set<String> = ["synonym"]

    func test_coldStart_abstainsOnSubjectsTheJournalNeverMentions() throws {
        let gold = try ChatEvalCorpus.coldStartGold().filter { $0.match == "none" }
        XCTAssertFalse(gold.isEmpty, "the fixture must carry abstention questions")

        for size in Self.sizes {
            let (corpus, _) = try ChatEvalCorpus.coldStartCorpus(limit: size)
            for question in gold {
                let result = EntryRetriever.retrieve(
                    RetrievalQuery(currentMessage: question.query), entries: corpus
                )
                XCTAssertTrue(
                    result.isEmpty || result.isAmbient,
                    "n=\(size) \(question.id) \"\(question.query)\" grounded against a journal "
                        + "that never mentions it"
                )
            }
        }
    }

    func test_coldStart_groundsQuestionsTheJournalAnswers() throws {
        let gold = try ChatEvalCorpus.coldStartGold().filter { $0.match != "none" }
        let embeddings = EmbeddingService.shared.isAvailable
        var missed: [String] = []

        for size in Self.sizes {
            let (corpus, idByUUID) = try ChatEvalCorpus.coldStartCorpus(limit: size)
            let present = Set(corpus.compactMap { idByUUID[$0.id] })

            for question in gold {
                // Out of this slice: a different question at this size.
                guard question.expectedEntryIDs.allSatisfy(present.contains) else { continue }
                let result = EntryRetriever.retrieve(
                    RetrievalQuery(currentMessage: question.query), entries: corpus
                )
                let returned = Set(result.entries.compactMap { idByUUID[$0.id] })
                let hit = !result.isAmbient && !result.isEmpty
                    && !returned.isDisjoint(with: Set(question.expectedEntryIDs))

                let label = "n=\(size) \(question.id) [\(question.category)] \"\(question.query)\""
                if Self.knownGaps.contains(question.category) {
                    if !hit { missed.append("\(label) — known gap") }
                    continue
                }
                if Self.embeddingDependent.contains(question.category), !embeddings {
                    missed.append("\(label) — skipped, no NLEmbedding")
                    continue
                }
                XCTAssertTrue(hit, "\(label) did not ground; returned \(returned.sorted())")
            }
        }
        if !missed.isEmpty {
            print("[ColdStartRetrievalGate] not asserted:\n  " + missed.joined(separator: "\n  "))
        }
    }

    /// The small-corpus branch must be unreachable at the size the persona gold
    /// set was fitted on, so the mature numbers cannot move.
    func test_smallCorpusBranch_cannotReachTheMatureCorpus() {
        XCTAssertLessThan(RetrieverTuning.default.smallCorpusMax, 250)
    }
}
