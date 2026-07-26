//
//  SpikeA_SpotlightRecallTests.swift
//  MeetMementoTests
//
//  Spec 013 R2 — Spike A: Core Spotlight donation + retrieval quality.
//  Donates the full fixture corpus (Fixtures/corpus/*.json) and measures
//  recall@5 for the gold question set (Fixtures/gold/questions.resolved.json)
//  against the ≥ 0.85 bar (Gate α, half 1; standing gate spec 016 R8).
//
//  Deliberately env-gated so it never runs in normal CI/local suites:
//    TEST_RUNNER_SPIKE_A=1 \
//    TEST_RUNNER_SPIKE_A_FIXTURES=/path/to/repo/Fixtures \
//    xcodebuild test ... -only-testing:MeetMementoTests/SpikeA_SpotlightRecallTests
//
//  Retrieval path note: this measures the deterministic index+query half
//  (CSUserQuery ranked results — the same engine behind system Spotlight),
//  not the LLM-driven SpotlightSearchTool loop; the tool adds query
//  reformulation on top, so this number is the retrieval floor, not the
//  ceiling. Simulator-runnable; re-run on device alongside Spike C.
//

import XCTest
import CoreSpotlight
import UniformTypeIdentifiers

final class SpikeA_SpotlightRecallTests: XCTestCase {

    // MARK: Fixture schemas

    private struct FixtureEntry: Decodable {
        let id: String
        let createdAt: String
        let source: String
        let transcript: String
        let seedMoods: [String]?
    }

    private struct GoldFile: Decodable {
        let questions: [GoldQuestion]
    }

    private struct GoldQuestion: Decodable {
        let id: String
        let category: String
        let query: String
        let expectedEntryIDs: [String]
        let match: String // "all" | "any" | "none"
    }

    private static let domain = "spike-a.memento"

    // MARK: Test

    func test_spikeA_donateCorpus_measureRecallAt5() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["SPIKE_A"] == "1" else {
            throw XCTSkip("Spike A runs only with TEST_RUNNER_SPIKE_A=1 (spec 013 R2)")
        }
        guard let fixturesPath = env["SPIKE_A_FIXTURES"], !fixturesPath.isEmpty else {
            return XCTFail("TEST_RUNNER_SPIKE_A_FIXTURES must point at the repo's Fixtures directory")
        }
        guard CSSearchableIndex.isIndexingAvailable() else {
            throw XCTSkip("Core Spotlight indexing unavailable in this environment — run Spike A on a device")
        }

        // 1. Load corpus + gold set from the host filesystem.
        let fixturesURL = URL(fileURLWithPath: fixturesPath)
        let corpusDir = fixturesURL.appendingPathComponent("corpus")
        let corpusFiles = try FileManager.default.contentsOfDirectory(at: corpusDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var entries: [FixtureEntry] = []
        for file in corpusFiles {
            entries.append(contentsOf: try JSONDecoder().decode([FixtureEntry].self, from: Data(contentsOf: file)))
        }
        XCTAssertGreaterThanOrEqual(entries.count, 250, "corpus should be the full 262-entry set")

        let goldURL = fixturesURL.appendingPathComponent("gold/questions.resolved.json")
        let gold = try JSONDecoder().decode(GoldFile.self, from: Data(contentsOf: goldURL)).questions
        XCTAssertGreaterThanOrEqual(gold.count, 40)

        // 2. Clean slate, then donate everything in batches.
        let index = CSSearchableIndex.default()
        try await index.deleteSearchableItems(withDomainIdentifiers: [Self.domain])

        let isoParser = ISO8601DateFormatter()
        let items: [CSSearchableItem] = entries.map { entry in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            let firstLine = entry.transcript
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first.map(String.init) ?? entry.id
            attrs.title = String(firstLine.prefix(80))
            attrs.contentDescription = entry.transcript
            attrs.textContent = entry.transcript
            attrs.keywords = entry.seedMoods
            attrs.contentCreationDate = isoParser.date(from: entry.createdAt)
            let item = CSSearchableItem(
                uniqueIdentifier: entry.id,
                domainIdentifier: Self.domain,
                attributeSet: attrs
            )
            item.expirationDate = .distantFuture
            return item
        }
        for batch in stride(from: 0, to: items.count, by: 50).map({ Array(items[$0..<min($0 + 50, items.count)]) }) {
            try await index.indexSearchableItems(batch)
        }

        // 3. Wait for the index to catch up (no readiness API exists — V26
        //    resolved negative — so probe until a known entry is queryable).
        let probeDeadline = Date().addingTimeInterval(60)
        var indexReady = false
        while Date() < probeDeadline {
            let probeHits = try await runQuery("pottery", limit: 5)
            if !probeHits.isEmpty { indexReady = true; break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        XCTAssertTrue(indexReady, "index never became queryable within 60s of donation")

        // 4. Run the gold set — two conditions:
        //    (a) raw NL question (first run measured this at 0.067: CSUserQuery
        //        token-ANDs the full question, so raw NL retrieves ~nothing);
        //    (b) extracted terms with progressive relaxation — a deterministic
        //        floor for what SpotlightSearchTool's LLM reformulation does.
        struct Row { let q: GoldQuestion; let top5: [String]; let credit: Double }
        func score(_ q: GoldQuestion, _ top5: [String]) -> Double {
            let found = Set(top5).intersection(Set(q.expectedEntryIDs))
            switch q.match {
            case "any":  return found.isEmpty ? 0 : 1
            case "none": return top5.isEmpty ? 1 : 0
            default:     return q.expectedEntryIDs.isEmpty ? 1
                                : Double(found.count) / Double(q.expectedEntryIDs.count) // "all": recall = found/expected
            }
        }
        var rawRows: [Row] = []
        var termRows: [Row] = []
        for q in gold {
            let rawTop5 = try await runQuery(q.query, limit: 5)
            rawRows.append(Row(q: q, top5: rawTop5, credit: score(q, rawTop5)))

            let top5 = try await runExtractedTermsQuery(for: q.query, limit: 5)
            termRows.append(Row(q: q, top5: top5, credit: score(q, top5)))
        }
        let rows = termRows

        // 5. Score + report. Aggregate is the mean per-question credit
        //    (questions.json's own scoring note); strict = fraction fully satisfied.
        let aggregate = rows.map(\.credit).reduce(0, +) / Double(rows.count)
        let strict = Double(rows.filter { $0.credit >= 1.0 }.count) / Double(rows.count)
        var perCategory: [String: (sum: Double, n: Int)] = [:]
        for r in rows {
            perCategory[r.q.category, default: (0, 0)].sum += r.credit
            perCategory[r.q.category]!.n += 1
        }

        let rawAggregate = rawRows.map(\.credit).reduce(0, +) / Double(rawRows.count)

        var report = "\n===== SPIKE A RESULT =====\n"
        report += "corpus: \(entries.count) entries | questions: \(rows.count)\n"
        report += String(format: "recall@5, extracted terms (mean credit): %.3f   [bar: 0.850]\n", aggregate)
        report += String(format: "recall@5, raw NL question:               %.3f   (control)\n", rawAggregate)
        report += String(format: "strictly satisfied (extracted):          %.3f\n", strict)
        for (cat, v) in perCategory.sorted(by: { $0.key < $1.key }) {
            report += String(format: "  %-10s %.3f  (n=%d)\n", (cat as NSString).utf8String!, v.sum / Double(v.n), v.n)
        }
        report += "misses (credit < 1):\n"
        for r in rows where r.credit < 1.0 {
            report += "  \(r.q.id) [\(r.q.category)/\(r.q.match)] credit=\(String(format: "%.2f", r.credit)) top5=\(r.top5)\n"
        }
        report += "==========================\n"
        print(report)

        // Attach the report so it survives in the xcresult bundle.
        let attachment = XCTAttachment(string: report)
        attachment.name = "SpikeA-recall-report"
        attachment.lifetime = .keepAlways
        add(attachment)

        // The gate itself: recorded, not asserted — spec 013 R2 wants the
        // number written back to the spec either way; a failing number is a
        // Plan-B trigger, not a broken build. Assert only sanity.
        XCTAssertGreaterThan(aggregate, 0.0, "zero recall means the query path itself is broken")
    }

    // MARK: Term extraction (deterministic stand-in for the tool's LLM reformulation)

    private static let stopwords: Set<String> = [
        "a", "about", "after", "all", "am", "an", "and", "any", "are", "at", "back",
        "be", "been", "before", "can", "could", "day", "did", "do", "does", "ever",
        "finally", "first", "for", "from", "get", "go", "got", "had", "happened",
        "has", "have", "how", "i", "in", "into", "is", "it", "last", "like", "me",
        "my", "new", "of", "on", "one", "our", "out", "said", "say", "see", "she",
        "should", "since", "so", "start", "started", "tell", "than", "that", "the",
        "there", "these", "they", "things", "this", "time", "to", "was", "we",
        "were", "what", "when", "which", "who", "will", "with", "would", "wrote",
        "write", "written", "year", "you",
    ]

    private func extractTerms(_ query: String) -> [String] {
        query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !Self.stopwords.contains($0) }
    }

    /// Progressive relaxation: all extracted terms, then the 2 most
    /// distinctive (longest), then the single most distinctive — first
    /// non-empty result wins. Mirrors a minimal tool-loop retry.
    private func runExtractedTermsQuery(for query: String, limit: Int) async throws -> [String] {
        let terms = extractTerms(query)
        guard !terms.isEmpty else { return try await runQuery(query, limit: limit) }
        let byLength = terms.sorted { $0.count > $1.count }
        var attempts: [[String]] = [terms]
        if terms.count > 2 { attempts.append(Array(byLength.prefix(2))) }
        if terms.count > 1 { attempts.append(Array(byLength.prefix(1))) }
        for attempt in attempts {
            let hits = try await runQuery(attempt.joined(separator: " "), limit: limit)
            if !hits.isEmpty { return hits }
        }
        return []
    }

    // MARK: Query helper

    private func runQuery(_ text: String, limit: Int) async throws -> [String] {
        let context = CSUserQueryContext()
        context.fetchAttributes = ["title"]
        context.maxResultCount = limit
        context.enableRankedResults = true
        let query = CSUserQuery(userQueryString: text, userQueryContext: context)
        var ids: [String] = []
        do {
            for try await response in query.responses {
                if case .item(let item) = response {
                    ids.append(item.item.uniqueIdentifier)
                    if ids.count >= limit { break }
                }
            }
        } catch {
            // Cancellation after hitting the limit is fine; anything else is real.
            if ids.isEmpty { throw error }
        }
        return ids
    }
}
