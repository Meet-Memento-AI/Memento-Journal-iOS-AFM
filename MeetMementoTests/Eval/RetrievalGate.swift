import XCTest
@testable import MeetMemento

/// Spec 044 R2 — SDK-free retrieval gate.
///
/// Loads the persona corpus + resolved gold set, runs `EntryRetriever.retrieve`
/// for every question, and writes recall@5 / precision@5 / MRR / abstention
/// accuracy to `.eval-runs/retrieval/`. Report-only: no threshold `XCTAssert`
/// until two measured runs are warehoused (044 / 022).
///
/// ```
/// TEST_RUNNER_RETRIEVAL_GATE=1 xcodebuild test \
///   -scheme MeetMemento \
///   -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
///   -only-testing:MeetMementoTests/RetrievalGate
/// ```
///
/// `RETRIEVER_GRID=1` grid-searches hybrid weights on the same gold and writes
/// `grid.md` beside the report. Import later with `kind=harness_retrieval`.
final class RetrievalGate: XCTestCase {

    private static let promptCap = EntryRetriever.maxEntries

    func test_retrievalGate_reportOnly() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["TEST_RUNNER_RETRIEVAL_GATE"] == "1" || env["RETRIEVAL_GATE"] == "1",
            "set TEST_RUNNER_RETRIEVAL_GATE=1"
        )

        let (corpus, fixtureByUUID) = try ChatEvalCorpus.personaCorpus()
        let gold = try ChatEvalCorpus.goldQuestions()
        XCTAssertGreaterThanOrEqual(corpus.count, 250, "persona corpus must be present")
        EntryRetriever.warmEmbeddings(corpus, generation: 1)

        let scored = Self.run(
            gold: gold, corpus: corpus, fixtureByUUID: fixtureByUUID,
            tuning: .default
        )
        let report = Self.renderReport(scored)
        print(report)
        Self.write(report: report, items: scored, extra: nil)

        if env["RETRIEVER_GRID"] == "1" {
            let grid = Self.gridSearch(gold: gold, corpus: corpus, fixtureByUUID: fixtureByUUID)
            print(grid)
            Self.write(report: report, items: scored, extra: ("grid.md", grid))
        }
    }

    // MARK: - Scoring

    fileprivate struct Item {
        let id: String
        let category: String
        let match: String
        let query: String
        let expected: [String]
        let top: [String]
        let ambient: Bool
        let empty: Bool
        let ranks: [String: Int]
        let recall: Double
        let precision: Double
        let reciprocalRank: Double
        let abstainedCorrectly: Bool?
        let hit: Bool
    }

    fileprivate struct Summary {
        let items: [Item]
        let answerableCount: Int
        let recallAt5: Double
        let precisionAt5: Double
        let mrr: Double
        let abstentionAccuracy: Double
        let hitCount: Int
        let trapCount: Int
        let trapLeaks: Int
    }

    fileprivate static func run(
        gold: [ChatEvalCorpus.GoldQuestion],
        corpus: [Entry],
        fixtureByUUID: [UUID: String],
        tuning: RetrieverTuning
    ) -> Summary {
        let limits = RetrievalLimits(maxEntries: promptCap, maxContentChars: EntryRetriever.maxContentChars)
        var items: [Item] = []
        items.reserveCapacity(gold.count)

        for question in gold {
            let result = EntryRetriever.retrieve(
                RetrievalQuery(currentMessage: question.query, historyContext: nil),
                entries: corpus,
                tuning: tuning,
                limits: limits
            )
            items.append(score(question, result: result, fixtureByUUID: fixtureByUUID))
        }
        return summarize(items)
    }

    private static func score(
        _ question: ChatEvalCorpus.GoldQuestion,
        result: RetrievalResult,
        fixtureByUUID: [UUID: String]
    ) -> Item {
        let top = result.entries.compactMap { fixtureByUUID[$0.id] }
        let expected = question.expectedEntryIDs
        var ranks: [String: Int] = [:]
        for id in expected {
            if let idx = top.firstIndex(of: id) { ranks[id] = idx }
        }

        let expectedSet = Set(expected)
        let found = top.filter { expectedSet.contains($0) }
        let isNone = question.match == "none"
        let abstainedCorrectly: Bool?
        let recall: Double
        let precision: Double
        let rr: Double
        let hit: Bool

        if isNone {
            // Honesty trap: empty or ambient is correct; a strong topical hit is not.
            let ok = result.isEmpty || result.isAmbient
            abstainedCorrectly = ok
            recall = ok ? 1 : 0
            precision = ok ? 1 : 0
            rr = ok ? 1 : 0
            hit = ok
        } else {
            abstainedCorrectly = nil
            if expected.isEmpty {
                recall = result.isEmpty || result.isAmbient ? 1 : 0
            } else if question.match == "any" {
                recall = found.isEmpty ? 0 : 1
            } else {
                recall = Double(found.count) / Double(expected.count)
            }
            precision = top.isEmpty ? 0 : Double(found.count) / Double(top.count)
            if let first = top.firstIndex(where: { expectedSet.contains($0) }) {
                rr = 1.0 / Double(first + 1)
            } else {
                rr = 0
            }
            hit = recall > 0
        }

        return Item(
            id: question.id, category: question.category, match: question.match,
            query: question.query, expected: expected, top: top,
            ambient: result.isAmbient, empty: result.isEmpty, ranks: ranks,
            recall: recall, precision: precision, reciprocalRank: rr,
            abstainedCorrectly: abstainedCorrectly, hit: hit
        )
    }

    private static func summarize(_ items: [Item]) -> Summary {
        let answerable = items.filter { $0.match != "none" }
        let traps = items.filter { $0.match == "none" }
        let recall = mean(answerable.map(\.recall))
        let precision = mean(answerable.map(\.precision))
        let mrr = mean(answerable.map(\.reciprocalRank))
        let abstention = traps.isEmpty ? 1 : mean(traps.map { $0.abstainedCorrectly == true ? 1 : 0 })
        return Summary(
            items: items,
            answerableCount: answerable.count,
            recallAt5: recall,
            precisionAt5: precision,
            mrr: mrr,
            abstentionAccuracy: abstention,
            hitCount: answerable.filter(\.hit).count,
            trapCount: traps.count,
            trapLeaks: traps.filter { $0.abstainedCorrectly != true }.count
        )
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Grid

    fileprivate struct GridRow {
        let tuning: RetrieverTuning
        let summary: Summary
    }

    /// Compact grid over the hybrid rank weights. `themeBoost` cannot be fit
    /// against this gold (no confirmed themes on the questions); it is held
    /// at the committed 0.5 and exercised by `ThemePriorTests`.
    private static func gridSearch(
        gold: [ChatEvalCorpus.GoldQuestion],
        corpus: [Entry],
        fixtureByUUID: [UUID: String]
    ) -> String {
        var rows: [GridRow] = []
        for semantic in [3.0, 5.0, 7.0] {
            for recency in [0.25, 0.5, 1.0] {
                for keywordMin in [1.5, 2.0, 2.5] {
                    var tuning = RetrieverTuning.default
                    tuning.semanticWeight = semantic
                    tuning.recencyWeight = recency
                    tuning.keywordSignalMin = keywordMin
                    let summary = run(
                        gold: gold, corpus: corpus, fixtureByUUID: fixtureByUUID,
                        tuning: tuning
                    )
                    rows.append(GridRow(tuning: tuning, summary: summary))
                }
            }
        }
        rows.sort {
            if $0.summary.recallAt5 != $1.summary.recallAt5 {
                return $0.summary.recallAt5 > $1.summary.recallAt5
            }
            if $0.summary.mrr != $1.summary.mrr {
                return $0.summary.mrr > $1.summary.mrr
            }
            return $0.summary.abstentionAccuracy > $1.summary.abstentionAccuracy
        }

        var out = "# Retriever grid (`RETRIEVER_GRID=1`)\n\n"
        out += "Held constant: `passageMeanWeight=0.15`, `themeBoost=0.5` "
        out += "(themeBoost is reorder-only and needs confirmed theme ids; "
        out += "this gold set does not supply them).\n\n"
        out += "| rank | semantic | recency | keywordMin | recall@5 | precision@5 | MRR | abstention |\n"
        out += "|---:|---:|---:|---:|---:|---:|---:|---:|\n"
        for (index, row) in rows.enumerated() {
            out += String(
                format: "| %d | %.2f | %.2f | %.2f | %.3f | %.3f | %.3f | %.3f |\n",
                index + 1,
                row.tuning.semanticWeight,
                row.tuning.recencyWeight,
                row.tuning.keywordSignalMin,
                row.summary.recallAt5,
                row.summary.precisionAt5,
                row.summary.mrr,
                row.summary.abstentionAccuracy
            )
        }
        if let best = rows.first {
            out += "\nWinning row: semantic=\(best.tuning.semanticWeight) "
            out += "recency=\(best.tuning.recencyWeight) "
            out += "keywordMin=\(best.tuning.keywordSignalMin) "
            out += "→ recall@5=\(Self.pct(best.summary.recallAt5)).\n"
            out += "Committed defaults stay `semanticWeight=5.0`, `recencyWeight=0.5`, "
            out += "`keywordSignalMin=2.0` unless this table shows a clear winner "
            out += "that does not leak honesty traps.\n"
        }
        return out
    }

    // MARK: - Report I/O

    private static func renderReport(_ summary: Summary) -> String {
        var out = "# RetrievalGate (spec 044 R2)\n\n"
        out += "kind: `harness_retrieval` · prompt cap \(promptCap) · report-only "
        out += "(no 0.85 bar on this run)\n\n"
        out += "## Headline\n\n"
        out += "| metric | value |\n|---|---|\n"
        out += "| questions | \(summary.items.count) |\n"
        out += "| answerable | \(summary.answerableCount) |\n"
        out += "| recall@5 | **\(pct(summary.recallAt5))** (\(summary.hitCount)/\(summary.answerableCount) hit) |\n"
        out += "| precision@5 | \(pct(summary.precisionAt5)) |\n"
        out += "| MRR | \(pct(summary.mrr)) |\n"
        out += "| abstention accuracy | \(pct(summary.abstentionAccuracy)) "
        out += "(\(summary.trapCount - summary.trapLeaks)/\(summary.trapCount) traps quiet) |\n"
        out += "| ambient | \(summary.items.filter(\.ambient).count)/\(summary.items.count) |\n\n"

        out += "## Per question\n\n"
        out += "| id | match | hit | recall | top | query |\n|---|---|---|---:|---|---|\n"
        for item in summary.items {
            let mark = item.hit ? "yes" : "**no**"
            let top = item.top.isEmpty ? (item.ambient ? "ambient" : "empty") : item.top.joined(separator: ", ")
            out += "| \(item.id) | \(item.match) | \(mark) | \(pct(item.recall)) | \(top) | \(item.query) |\n"
        }

        let misses = summary.items.filter { $0.match != "none" && !$0.hit }
        if !misses.isEmpty {
            out += "\n## Misses\n\n"
            for item in misses {
                out += "### \(item.id) — \(item.query)\n"
                out += "- expected: \(item.expected.joined(separator: ", "))\n"
                out += "- ranks: \(item.expected.map { id in item.ranks[id].map(String.init) ?? "∅" }.joined(separator: ", "))\n"
                out += "- prompt: \(item.top.joined(separator: ", "))\n"
                out += "- ambient: \(item.ambient)\n\n"
            }
        }
        return out
    }

    private static func pct(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func write(report: String, items summary: Summary, extra: (String, String)?) {
        let dir: URL
        if let path = ProcessInfo.processInfo.environment["RETRIEVAL_GATE_OUT"], !path.isEmpty {
            dir = URL(fileURLWithPath: path)
        } else {
            dir = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".eval-runs")
                .appendingPathComponent("retrieval")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? report.write(to: dir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)

        let payload: [String: Any] = [
            "kind": "harness_retrieval",
            "promptCap": promptCap,
            "reportOnly": true,
            "metrics": [
                "recall@5": summary.recallAt5,
                "precision@5": summary.precisionAt5,
                "mrr": summary.mrr,
                "abstentionAccuracy": summary.abstentionAccuracy,
                "answerable": summary.answerableCount,
                "hits": summary.hitCount,
                "traps": summary.trapCount,
                "trapLeaks": summary.trapLeaks
            ],
            "items": summary.items.map { item -> [String: Any] in
                [
                    "id": item.id,
                    "category": item.category,
                    "match": item.match,
                    "query": item.query,
                    "expected": item.expected,
                    "top": item.top,
                    "ambient": item.ambient,
                    "empty": item.empty,
                    "ranks": item.ranks,
                    "recall": item.recall,
                    "precision": item.precision,
                    "mrr": item.reciprocalRank,
                    "hit": item.hit
                ]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("report.json"))
        }

        var csv = "id,match,hit,recall,precision,mrr,ambient,empty,expected,top,query\n"
        for item in summary.items {
            let expected = item.expected.joined(separator: ";")
            let top = item.top.joined(separator: ";")
            csv += "\(item.id),\(item.match),\(item.hit),\(pct(item.recall)),\(pct(item.precision)),\(pct(item.reciprocalRank)),\(item.ambient),\(item.empty),\"\(expected)\",\"\(top)\",\"\(item.query.replacingOccurrences(of: "\"", with: "'"))\"\n"
        }
        try? csv.write(to: dir.appendingPathComponent("items.csv"), atomically: true, encoding: .utf8)

        if let extra {
            try? extra.1.write(to: dir.appendingPathComponent(extra.0), atomically: true, encoding: .utf8)
        }
    }
}
