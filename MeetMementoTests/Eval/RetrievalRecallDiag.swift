import XCTest
@testable import MeetMemento

/// Where does a wrong citation actually come from?
///
/// The chat gate scores the *reply*: it can say "cited e-2026-01-15-1, expected
/// e-2026-01-08-1" but not whether the expected entry was ever in the prompt.
/// Those are two different defects with two different fixes:
///
///   - **retrieval miss** — the expected entry never reached the model. No
///     amount of prompt work can fix it; `EntryRetriever` has to rank better.
///   - **selection miss** — the expected entry was in the prompt and the model
///     cited a neighbour anyway. Retrieval is fine; the prompt or
///     `reconcileCitations` is at fault.
///
/// Retrieval is deterministic given (query, entries) and needs no model, so
/// this runs in seconds against the same 262-entry persona corpus the gate
/// uses, reproducing the query `prepareAsk` builds for a journal question with
/// no history (`.currentWeighted`, `historyContext` nil).
final class RetrievalRecallDiag: XCTestCase {

    /// What `prepareAsk` hands the prompt: pool of 20, sliced to 5.
    private static let promptCap = EntryRetriever.maxEntries      // 5
    private static let poolCap = SessionCandidatePool.capacity    // 20

    private struct Row {
        let id: String
        let category: String
        let match: String
        let query: String
        let expected: [String]
        let ranks: [String: Int?]      // expected id → rank in the full ordering
        let top: [String]              // the first `promptCap` ids actually sent
        let ambient: Bool
        let strongCount: Int

        var inPrompt: [String] { expected.filter { (ranks[$0] ?? nil).map { $0 < RetrievalRecallDiag.promptCap } ?? false } }
        var inPool: [String] { expected.filter { (ranks[$0] ?? nil).map { $0 < RetrievalRecallDiag.poolCap } ?? false } }
        var missing: [String] { expected.filter { (ranks[$0] ?? nil) == nil } }
    }

    func test_retrievalRecallOnGoldSet() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RETRIEVAL_DIAG"] == "1",
                          "set TEST_RUNNER_RETRIEVAL_DIAG=1")

        let (corpus, fixtureByUUID) = try ChatEvalCorpus.personaCorpus()
        let gold = try ChatEvalCorpus.goldQuestions()
        XCTAssertGreaterThanOrEqual(corpus.count, 250)

        // Warm the vector cache once, exactly as the app does before a turn.
        EntryRetriever.warmEmbeddings(corpus, generation: 1)

        // A limit big enough that nothing is truncated, so a rank exists for
        // every entry retrieval was willing to return.
        let wide = RetrievalLimits(maxEntries: corpus.count, maxContentChars: 500)

        var rows: [Row] = []
        for question in gold {
            let result = EntryRetriever.retrieve(
                RetrievalQuery(currentMessage: question.query, historyContext: nil),
                entries: corpus, limits: wide
            )
            let orderedIDs = result.entries.compactMap { fixtureByUUID[$0.id] }
            var ranks: [String: Int?] = [:]
            for expected in question.expectedEntryIDs {
                ranks[expected] = orderedIDs.firstIndex(of: expected)
            }
            rows.append(Row(
                id: question.id, category: question.category, match: question.match,
                query: question.query, expected: question.expectedEntryIDs,
                ranks: ranks, top: Array(orderedIDs.prefix(Self.promptCap)),
                ambient: result.isAmbient, strongCount: result.entries.count
            ))
        }

        let report = Self.render(rows)
        print(report)
        Self.write(report, rows)
    }

    // MARK: - Report

    private static func render(_ rows: [Row]) -> String {
        var out = "# Retrieval recall on the gold set\n\n"
        out += "corpus 262 entries · prompt cap \(promptCap) · pool cap \(poolCap)\n\n"

        let answerable = rows.filter { !$0.expected.isEmpty }
        let traps = rows.filter { $0.expected.isEmpty }

        let recall5 = answerable.filter { !$0.inPrompt.isEmpty }.count
        let recall20 = answerable.filter { !$0.inPool.isEmpty }.count
        let full5 = answerable.filter { $0.inPrompt.count == $0.expected.count }.count

        out += "## Headline\n\n"
        out += "| metric | value |\n|---|---|\n"
        out += "| answerable questions | \(answerable.count) |\n"
        out += "| recall@5 (any expected entry reached the prompt) | **\(recall5)/\(answerable.count)** |\n"
        out += "| recall@20 (any expected entry reached the pool) | \(recall20)/\(answerable.count) |\n"
        out += "| full recall@5 (every expected entry reached the prompt) | \(full5)/\(answerable.count) |\n"
        out += "| ambient (no strong signal at all) | \(rows.filter(\.ambient).count)/\(rows.count) |\n"
        out += "| honesty traps returning entries anyway | \(traps.filter { !$0.top.isEmpty }.count)/\(traps.count) |\n\n"

        out += "## Per question\n\n"
        out += "| id | cat | rank of expected | in prompt | ambient | query |\n|---|---|---|---|---|---|\n"
        for r in rows {
            let rankText: String
            if r.expected.isEmpty {
                rankText = "— (trap)"
            } else {
                rankText = r.expected.map { id in
                    (r.ranks[id] ?? nil).map(String.init) ?? "∅"
                }.joined(separator: ", ")
            }
            let hit = r.expected.isEmpty ? (r.top.isEmpty ? "ok" : "**leaks**")
                                         : (r.inPrompt.isEmpty ? "**no**" : "yes")
            out += "| \(r.id) | \(r.category) | \(rankText) | \(hit) | \(r.ambient ? "yes" : "") | \(r.query) |\n"
        }

        out += "\n## Retrieval misses — expected entry outside the prompt window\n\n"
        for r in answerable where r.inPrompt.isEmpty {
            out += "### \(r.id) — \(r.query)\n"
            out += "- expected: \(r.expected.joined(separator: ", "))\n"
            out += "- rank: \(r.expected.map { (r.ranks[$0] ?? nil).map(String.init) ?? "not returned" }.joined(separator: ", "))\n"
            out += "- prompt got: \(r.top.joined(separator: ", "))\n"
            out += "- ambient: \(r.ambient)\n\n"
        }
        return out
    }

    private static func write(_ text: String, _ rows: [Row]) {
        let dir = ProcessInfo.processInfo.environment["RETRIEVAL_DIAG_OUT"].map(URL.init(fileURLWithPath:))
            ?? URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".eval-runs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: dir.appendingPathComponent("retrieval-recall.md"), atomically: true, encoding: .utf8)

        let json: [[String: Any]] = rows.map { r in
            [
                "id": r.id, "category": r.category, "match": r.match, "query": r.query,
                "expected": r.expected,
                "ranks": r.expected.reduce(into: [String: Any]()) { acc, id in
                    acc[id] = (r.ranks[id] ?? nil) ?? -1
                },
                "top": r.top, "ambient": r.ambient, "returned": r.strongCount
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("retrieval-recall.json"))
        }
    }
}
