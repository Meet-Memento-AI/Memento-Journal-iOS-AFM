import NaturalLanguage
import XCTest
@testable import MeetMemento

/// Which guard actually blocks a cold-start question?
///
/// `RetrievalRecallDiag` answers "was the expected entry in the prompt" on the
/// 262-entry persona corpus. Neither it nor `RetrievalGate` can run below 250
/// entries, so the retriever's constants have never been measured at the size a
/// new install actually has — which is exactly where the "I don't see anything"
/// replies are reported.
///
/// `hasSignal = clears && inWindow && lexicalWhereRequired`, and each conjunct
/// fails for a different reason with a different fix:
///
///   - **`clears` false** — the cosine threshold or the keyword bar is too high
///     for this corpus size. Fixable by tuning constants.
///   - **`lexicalWhereRequired` false** — the question and the entry share no
///     literal content word ("sleeping" vs "slept"). No threshold can fix that;
///     it needs wider lexical matching.
///
/// This prints the conjuncts per entry so the choice is made from a table
/// rather than from reasoning. Report-only; it asserts nothing about quality.
///
/// ```
/// COLD_START_DIAG=1 DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
/// xcodebuild test -scheme MeetMemento \
///   -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
///   -only-testing:MeetMementoTests/ColdStartRetrievalDiag
/// ```
final class ColdStartRetrievalDiag: XCTestCase {

    private static let sizes = [3, 5, 8]

    func test_coldStartRetrievalDiag() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["COLD_START_DIAG"] == "1" || env["TEST_RUNNER_COLD_START_DIAG"] == "1",
            "set COLD_START_DIAG=1"
        )

        let gold = try ChatEvalCorpus.coldStartGold()
        var report = "# Cold-start retrieval diagnostic\n\n"
        report += "NLEmbedding available: \(EmbeddingService.shared.isAvailable)\n"
        report += "keywordSignalMin=\(RetrieverTuning.default.keywordSignalMin) "
        report += "semanticFloorAbs=\(RetrieverTuning.default.semanticFloorAbs) "
        report += "minCorpusForSigma=\(RetrieverTuning.default.minCorpusForSigma) "
        report += "idfMinCorpus=\(EntryRetriever.idfMinCorpus)\n\n"

        for n in Self.sizes {
            let (corpus, idByUUID) = try ChatEvalCorpus.coldStartCorpus(limit: n)
            EntryRetriever.warmEmbeddings(corpus, generation: UInt64(n))
            report += "## n = \(n)  (\(corpus.compactMap { idByUUID[$0.id] }.joined(separator: ", ")))\n\n"

            for question in gold {
                let reachable = question.expectedEntryIDs.allSatisfy { expected in
                    corpus.contains { idByUUID[$0.id] == expected }
                }
                // A question whose expected entry is not in this slice is not
                // answerable at this size — it is a different question there.
                guard reachable else { continue }
                report += Self.row(for: question, corpus: corpus, idByUUID: idByUUID)
            }
        }

        print(report)
        Self.write(report)
    }

    // MARK: - One question

    private static func row(
        for question: ChatEvalCorpus.GoldQuestion,
        corpus: [Entry],
        idByUUID: [UUID: String]
    ) -> String {
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: question.query),
            entries: corpus
        )
        let outcome = result.isEmpty ? "empty" : (result.isAmbient ? "AMBIENT" : "grounded")
        let cited = result.entries.compactMap { idByUUID[$0.id] }.joined(separator: ",")

        let tuning = RetrieverTuning.default
        let terms = EntryRetriever.tokenize(question.query)
        let hashes = corpus.map {
            EmbeddingService.contentHash(title: $0.title, text: $0.text)
        }
        let smallCorpus = corpus.count <= tuning.smallCorpusMax
        let (keyword, documentFrequency) = EntryRetriever.keywordScores(
            entries: corpus, terms: terms, hashes: hashes,
            neighborDistance: smallCorpus ? tuning.neighborDistance : nil
        )
        let queryWeight = documentFrequency
            .map { EntryRetriever.termWeight(documentFrequency: $0, corpus: corpus.count) }
            .reduce(0, +)

        let queryVector = EmbeddingService.shared.embedQuery(question.query)
        var cosines: [Double?] = []
        for (index, entry) in corpus.enumerated() {
            guard let queryVector else { cosines.append(nil); continue }
            let chunked = PassageChunker.chunk(
                title: entry.title, text: entry.text, contentHash: hashes[index]
            )
            let scored = EntryRetriever.passageCosine(
                current: queryVector,
                history: nil,
                passages: EmbeddingService.shared.passageVectors(
                    id: entry.id, passages: chunked.passages,
                    contentHash: hashes[index], language: chunked.language
                ),
                wholeEntry: EmbeddingService.shared.entryVector(
                    id: entry.id, text: EntryRetriever.embedText(for: entry),
                    contentHash: hashes[index]
                ),
                tuning: tuning
            )
            cosines.append(scored.cosine)
        }
        let threshold = EntryRetriever.semanticThreshold(
            cosines: cosines.compactMap { $0 }, highBar: false, tuning: tuning
        )

        var out = "### \(question.id) [\(question.category)/\(question.match)] "
        out += "\"\(question.query)\"\n"
        out += "terms: \(terms.isEmpty ? "—" : terms.joined(separator: " ")) | "
        out += "queryWeight: \(fmt(queryWeight)) | threshold: \(fmt(threshold))\n"
        out += "expected: \(question.expectedEntryIDs.joined(separator: ",")) | "
        out += "outcome: \(outcome) | returned: \(cited.isEmpty ? "—" : cited)\n\n"
        out += "| entry | cosine | ≥thr | keyword | covers | lexical | hasSignal |\n"
        out += "|---|---|---|---|---|---|---|\n"
        for (index, entry) in corpus.enumerated() {
            let id = idByUUID[entry.id] ?? "?"
            let cosine = cosines[index]
            let clearsCosine = cosine.map { $0 >= threshold } ?? false
            let clearsKeyword = keyword[index] >= tuning.keywordSignalMin
            let covers = queryWeight > 0 && keyword[index] >= queryWeight * 0.9
            let lexical = terms.isEmpty || keyword[index] > 0
            let hasSignal = (clearsCosine || clearsKeyword || covers) && lexical
            let mark = question.expectedEntryIDs.contains(id) ? "**\(id)**" : id
            out += "| \(mark) | \(cosine.map(fmt) ?? "—") | \(clearsCosine ? "Y" : "n") "
            out += "| \(fmt(keyword[index]))\(clearsKeyword ? " Y" : "") | \(covers ? "Y" : "n") "
            out += "| \(lexical ? "Y" : "**n**") | \(hasSignal ? "Y" : "n") |\n"
        }
        if smallCorpus, !terms.isEmpty {
            var vocabulary: Set<String> = []
            for (index, entry) in corpus.enumerated() {
                let sets = EmbeddingService.shared.wordSets(
                    id: entry.id, contentHash: hashes[index], title: entry.title, text: entry.text
                )
                vocabulary.formUnion(sets.title)
                vocabulary.formUnion(sets.text)
            }
            // A generous bar here on purpose: the report is for choosing
            // `neighborDistance`, so it has to show what sits just outside it.
            let shown = terms.map { term -> String in
                let near = EmbeddingService.shared
                    .wordsNear(term, in: vocabulary, maxDistance: 1.1)
                    .subtracting([term])
                    .map { word -> String in
                        let d = EmbeddingService.shared.wordDistance(term, word) ?? 9
                        let mark = d <= tuning.neighborDistance ? "" : " (out)"
                        return "\(word)=\(String(format: "%.2f", d))\(mark)"
                    }
                return "\(term)~{\(near.sorted().joined(separator: ","))}"
            }
            out += "\nnear words in this corpus: \(shown.joined(separator: " "))\n"
        }
        return out + "\n"
    }

    private static func fmt(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    /// Beside the other eval reports, so a run can be attached to a PR.
    private static func write(_ report: String) {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Eval
            .deletingLastPathComponent()   // MeetMementoTests
            .deletingLastPathComponent()   // repo
            .appendingPathComponent(".eval-runs/cold-start")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? report.write(to: dir.appendingPathComponent("diag-\(stamp).md"),
                          atomically: true, encoding: .utf8)
    }
}
