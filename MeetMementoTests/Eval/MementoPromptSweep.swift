import XCTest
@testable import MeetMemento

/// A 1,000-generation exploratory sweep through the exact path `AIChatView`
/// uses, against the full 262-entry persona corpus.
///
/// This is **not** a gate. Nothing here fails the build on a bad answer — the
/// point is to produce a large, honest sample of what Memento says to ordinary
/// questions so a human can read it. Mechanical violations from
/// `ChatEvalScoring` are recorded alongside each reply purely as a reading aid:
/// they mark the replies most worth looking at first.
///
/// Run it:
/// ```
/// TEST_RUNNER_SWEEP=1 \
/// DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
/// xcodebuild test -scheme MeetMemento \
///   -destination 'platform=iOS Simulator,id=<iOS 27 device>' \
///   -parallel-testing-enabled NO -test-timeouts-enabled NO \
///   -only-testing:MeetMementoTests/MementoPromptSweep
/// ```
///
/// At ~6s per generation the full sweep is roughly 100 minutes, which is longer
/// than any single `xcodebuild` invocation should be trusted to survive. So the
/// runner appends one JSON object per line as it goes and skips prompt indices
/// already present in the file: re-running resumes, and a killed run loses at
/// most one generation.
///
/// Environment (all via `TEST_RUNNER_` prefix):
///   `SWEEP=1`         — required, otherwise skipped
///   `SWEEP_OUT`       — output directory (default `.eval-runs/sweep`)
///   `SWEEP_MINUTES`   — stop cleanly after N minutes (default 45)
///   `SWEEP_LIMIT`     — cap generations this process (default: no cap)
///   `SWEEP_SHARD` / `SWEEP_SHARDS` — split the corpus across simulators
final class MementoPromptSweep: XCTestCase {

    // MARK: - Row

    private struct Row {
        let index: Int
        let category: String
        let question: String
        var body: String = ""
        var heading1: String = ""
        var heading2: String = ""
        var citations: [(id: String, date: String, excerpt: String)] = []
        var promptVersion: String = ""
        var zone: String = ""
        var degraded: Bool = false
        var seconds: Double = 0
        var error: String?
        var violations: [ChatEvalScoring.Violation] = []
        var hasHistory: Bool = false

        var json: [String: Any] {
            [
                "index": index,
                "category": category,
                "question": question,
                "body": body,
                "heading1": heading1,
                "heading2": heading2,
                "chars": body.count,
                "words": body.split(whereSeparator: { $0.isWhitespace }).count,
                "citations": citations.map { ["id": $0.id, "date": $0.date, "excerpt": $0.excerpt] },
                "citationCount": citations.count,
                "promptVersion": promptVersion,
                "zone": zone,
                "degraded": degraded,
                "seconds": seconds,
                "error": error ?? "",
                "hasHistory": hasHistory,
                "violations": violations.map { ["code": $0.code, "detail": $0.detail] },
                "gatingViolations": ChatEvalScoring.gating(violations).count
            ]
        }
    }

    // MARK: - Sweep

    func test_thousandPromptSweep() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["SWEEP"] == "1", "sweep runs only with TEST_RUNNER_SWEEP=1")

        let service = FoundationModelsIntelligenceService.shared
        guard case .available = await service.availability() else {
            throw XCTSkip("on-device model unavailable on this destination")
        }

        let (persona, fixtureIDs) = try ChatEvalCorpus.personaCorpus()
        XCTAssertGreaterThanOrEqual(persona.count, 250, "expected the full fixture corpus")
        let index = ChatEvalScoring.QuoteIndex(persona)

        let all = PromptSweepCorpus.prompts()
        XCTAssertEqual(all.count, PromptSweepCorpus.targetCount)

        let outDir = Self.outputDirectory()
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let shard = Int(env["SWEEP_SHARD"] ?? "0") ?? 0
        let shards = max(1, Int(env["SWEEP_SHARDS"] ?? "1") ?? 1)
        // One file per shard. Four simulator processes appending to a single
        // file would race between `seekToEnd` and `write` and interleave lines;
        // the resume scan reads every shard file back, so the split costs
        // nothing.
        let jsonl = outDir.appendingPathComponent("sweep-\(shard).jsonl")

        let done = Self.completedIndices(in: outDir)
        let limit = Int(env["SWEEP_LIMIT"] ?? "") ?? Int.max
        let minutes = Double(env["SWEEP_MINUTES"] ?? "45") ?? 45

        var pending = all.filter { !done.contains($0.index) }
        if shards > 1 { pending = pending.filter { $0.index % shards == shard } }

        print("[sweep] \(done.count)/\(all.count) already recorded; "
              + "\(pending.count) pending on shard \(shard)/\(shards)")

        let clock = ContinuousClock()
        let startedAt = clock.now
        let deadline = startedAt + .seconds(minutes * 60)
        var produced = 0

        for prompt in pending {
            if produced >= limit { print("[sweep] limit reached"); break }
            if clock.now >= deadline { print("[sweep] time budget reached"); break }

            let row = await run(service: service, prompt: prompt,
                                corpus: persona, index: index, fixtureIDs: fixtureIDs)
            Self.append(row, to: jsonl)
            produced += 1

            if produced % 10 == 0 {
                let elapsed = Self.seconds(clock.now - startedAt)
                print(String(format: "[sweep] %d done this run (%.0fs, %.1fs/gen) — #%d %@",
                             produced, elapsed, elapsed / Double(produced),
                             prompt.index, prompt.category))
            }
        }

        let total = Self.completedIndices(in: outDir).count
        print("[sweep] corpus now holds \(total)/\(all.count) generations in \(outDir.path)")
        XCTAssertGreaterThan(produced, 0, "sweep produced nothing — model likely unavailable")
    }

    // MARK: - One generation

    private func run(service: FoundationModelsIntelligenceService,
                     prompt: PromptSweepCorpus.Prompt,
                     corpus: [Entry],
                     index: ChatEvalScoring.QuoteIndex,
                     fixtureIDs: [UUID: String]) async -> Row {
        var row = Row(index: prompt.index, category: prompt.category, question: prompt.text)
        row.hasHistory = !prompt.history.isEmpty

        let clock = ContinuousClock()
        let started = clock.now

        var result: AskResult?
        do {
            for try await event in service.askStream(prompt.text, history: prompt.history,
                                                     entries: corpus, images: []) {
                if case .final(let r) = event { result = r }
            }
        } catch {
            row.error = "\(error)"
        }
        row.seconds = Self.seconds(clock.now - started)

        guard row.error == nil else { return row }
        guard let result else {
            row.error = "stream ended without a final result"
            return row
        }

        row.body = result.body
        row.heading1 = result.heading1 ?? ""
        row.heading2 = result.heading2 ?? ""
        row.promptVersion = result.promptVersion
        row.zone = "\(result.zoneUsed)"
        row.degraded = result.wasDegraded

        let iso = ISO8601DateFormatter()
        row.citations = result.citations.map {
            (id: fixtureIDs[$0.entryId] ?? $0.entryId.uuidString,
             date: iso.string(from: $0.entryDate),
             excerpt: String($0.excerpt.prefix(220)))
        }

        if result.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            row.error = "empty body"
            return row
        }

        let turn = TurnClassifier.classify(prompt.text, hasHistory: !prompt.history.isEmpty)
        let channel = ReplyChannel.resolve(turn: turn, hasImages: false)
        let cap = channel.maximumResponseTokens(retrievalRan: !result.citations.isEmpty)

        row.violations =
            ChatEvalScoring.leaks(result.body)
            + ChatEvalScoring.ruleBreaks(result.body, isCasual: prompt.isCasual, index: index)
            + ChatEvalScoring.fabricatedQuotes(result.body, index: index)
            + ChatEvalScoring.uncitedQuote(result.body, citations: result.citations, index: index)
            + ChatEvalScoring.boldNotTheirWords(result.body, index: index)
            + ChatEvalScoring.runaway(result.body, capTokens: cap)

        return row
    }

    // MARK: - Output

    static func outputDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["SWEEP_OUT"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repo.appendingPathComponent(".eval-runs/sweep")
    }

    /// Which prompt indices the run directory already holds, across every
    /// shard file. Parsed leniently — a run killed mid-write can leave one
    /// truncated final line, and that must not stop the resume.
    private static func completedIndices(in dir: URL) -> Set<Int> {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("sweep") && $0.pathExtension == "jsonl" } ?? []
        var out = Set<Int>()
        for file in files {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let i = object["index"] as? Int else { continue }
                out.insert(i)
            }
        }
        return out
    }

    private static func append(_ row: Row, to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: row.json, options: [.sortedKeys]),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func seconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
    }
}
