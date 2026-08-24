import XCTest
@testable import MeetMemento

/// The chat quality gate (spec 022 R1/R2): ~100 live generations through the
/// path `AIChatView` actually uses, scored mechanically, all-or-nothing.
///
/// Run it:
/// ```
/// TEST_RUNNER_CHAT_EVAL=1 \
/// DEVELOPER_DIR=~/Downloads/Xcode-beta.app/Contents/Developer \
/// xcodebuild test -scheme MeetMemento \
///   -destination 'platform=iOS Simulator,id=<iOS 27 device>' \
///   -parallel-testing-enabled NO \
///   -only-testing:MeetMementoTests/ChatEvalGate
/// ```
///
/// Skipped by default so it never runs on the merge lane — it needs a live
/// model and ~15 minutes. This is deliberately unlike the `Diag*` suites, which
/// swallow their own errors and report green against a simulator that cannot
/// generate.
final class ChatEvalGate: XCTestCase {

    /// Reps per conversational scenario. Gold questions run once each.
    private static let reps = 5

    // MARK: - Scenarios

    private struct Scenario {
        let label: String
        let question: String
        let history: [ChatTurn]
        /// Casual turns must carry no markdown structure at all.
        let isCasual: Bool
        let reps: Int

        init(_ label: String, _ question: String,
             history: [ChatTurn] = [], isCasual: Bool = false, reps: Int = ChatEvalGate.reps) {
            self.label = label
            self.question = question
            self.history = history
            self.isCasual = isCasual
            self.reps = reps
        }
    }

    private static let journalHistory: [ChatTurn] = [
        ChatTurn(role: .user, text: "What did I write about the hike?"),
        ChatTurn(role: .assistant,
                 text: "You went up Mount Tamalpais with Maya, starting in fog before it broke open at the top.")
    ]

    private static let shareHistory: [ChatTurn] = [
        ChatTurn(role: .user, text: "I had a rough morning, honestly."),
        ChatTurn(role: .assistant, text: "That sounds like it sat heavily. What made the morning hard?")
    ]

    private static let longHistory: [ChatTurn] = [
        ChatTurn(role: .user, text: "What have I been writing about lately?"),
        ChatTurn(role: .assistant, text: "You have been circling work and sleep."),
        ChatTurn(role: .user, text: "That sounds right."),
        ChatTurn(role: .assistant, text: "What part of it feels most present today?"),
        ChatTurn(role: .user, text: "The sleep, mostly."),
        ChatTurn(role: .assistant, text: "The early waking has come up more than once. What changes on the nights it doesn't?")
    ]

    /// The conversational half — every shape that failed or misbehaved in the
    /// 2026-08-23 QA pass, plus the turn types that must stay ungrounded.
    private static let conversational: [Scenario] = [
        .init("casual", "Hey", isCasual: true),
        .init("about the app", "What can you do?"),
        .init("journal / broad", "What have I been writing about lately?"),
        .init("journal / entity", "Who is Maya?"),
        .init("no-match bait", "What color is my bicycle?"),
        .init("date bait", "What did I write on July 4th?"),
        .init("follow-up after journal", "Tell me more about that.", history: journalHistory),
        .init("follow-up after share", "Tell me more about that.", history: shareHistory),
        .init("journal question with history", "What else did I write that week?", history: journalHistory),
        .init("long history", "And what should I do with that?", history: longHistory),
        .init("share", "I had a rough day at work today")
    ]

    // MARK: - Sample

    private struct Sample {
        let scenario: String
        let question: String
        let rep: Int
        let corpus: String
        var body: String = ""
        var citations: Int = 0
        var promptVersion: String = ""
        var citedFixtureIDs: [String] = []
        var seconds: Double = 0
        var error: String?
        var violations: [ChatEvalScoring.Violation] = []

        var gating: [ChatEvalScoring.Violation] { ChatEvalScoring.gating(violations) }
        var passed: Bool { error == nil && !body.isEmpty && gating.isEmpty }
    }

    // MARK: - Gate

    func test_chatQualityGate() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["CHAT_EVAL"] == "1",
                          "chat eval runs only with TEST_RUNNER_CHAT_EVAL=1")

        let service = FoundationModelsIntelligenceService.shared
        guard case .available = await service.availability() else {
            throw XCTSkip("on-device model unavailable on this destination")
        }

        let (persona, fixtureIDs) = try ChatEvalCorpus.personaCorpus()
        let gold = try ChatEvalCorpus.goldQuestions()
        let attribution = ChatEvalCorpus.attributionCorpus
        XCTAssertGreaterThanOrEqual(persona.count, 250, "expected the full fixture corpus")

        let personaIndex = ChatEvalScoring.QuoteIndex(persona)
        let attributionIndex = ChatEvalScoring.QuoteIndex(attribution)

        var samples: [Sample] = []

        // --- Half 1: the gold set, one generation each, against the persona corpus.
        for question in gold {
            samples.append(await run(
                service: service, scenario: "gold/\(question.category)", question: question.query,
                history: [], isCasual: false, rep: 1,
                corpus: persona, corpusName: "persona", index: personaIndex,
                gold: question, fixtureIDs: fixtureIDs))
        }

        // --- Half 2: conversational shapes, repeated, against the attribution corpus.
        for scenario in Self.conversational {
            for rep in 1...scenario.reps {
                samples.append(await run(
                    service: service, scenario: scenario.label, question: scenario.question,
                    history: scenario.history, isCasual: scenario.isCasual, rep: rep,
                    corpus: attribution, corpusName: "attribution", index: attributionIndex))
            }
        }

        let report = Self.render(samples, fixtureIDs: fixtureIDs, goldCount: gold.count)
        Self.write(report, samples)
        print(report)

        let failures = samples.filter { !$0.passed }
        XCTAssertTrue(
            failures.isEmpty,
            """
            \(failures.count) of \(samples.count) generations failed the gate.
            \(Self.failureDigest(failures))
            Full report: \(Self.outputDirectory().path)
            """
        )
    }

    // MARK: - One generation

    private func run(service: FoundationModelsIntelligenceService,
                     scenario: String, question: String, history: [ChatTurn],
                     isCasual: Bool, rep: Int,
                     corpus: [Entry], corpusName: String,
                     index: ChatEvalScoring.QuoteIndex,
                     gold: ChatEvalCorpus.GoldQuestion? = nil,
                     fixtureIDs: [UUID: String] = [:]) async -> Sample {
        var sample = Sample(scenario: scenario, question: question, rep: rep, corpus: corpusName)
        let clock = ContinuousClock()
        let started = clock.now

        var result: AskResult?
        do {
            for try await event in service.askStream(question, history: history,
                                                     entries: corpus, images: []) {
                if case .final(let r) = event { result = r }
            }
        } catch {
            sample.error = "\(error)"
        }
        sample.seconds = Double((clock.now - started).components.seconds)

        guard sample.error == nil else { return sample }
        guard let result else {
            sample.error = "stream ended without a final result"
            return sample
        }

        sample.body = result.body
        sample.citations = result.citations.count
        sample.promptVersion = result.promptVersion

        if result.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sample.error = "empty body"
            return sample
        }

        let turn = TurnClassifier.classify(question, hasHistory: !history.isEmpty)
        let channel = ReplyChannel.resolve(turn: turn, hasImages: false)
        let cap = channel.maximumResponseTokens(retrievalRan: !result.citations.isEmpty)

        sample.violations =
            ChatEvalScoring.leaks(result.body)
            + ChatEvalScoring.ruleBreaks(result.body, isCasual: isCasual, index: index)
            + ChatEvalScoring.fabricatedQuotes(result.body, index: index)
            + ChatEvalScoring.uncitedQuote(result.body, citations: result.citations, index: index)
            + ChatEvalScoring.boldNotTheirWords(result.body, index: index)
            + ChatEvalScoring.runaway(result.body, capTokens: cap)

        // Is the answer right, not merely well-formed? Only the gold half can
        // be judged this way — the conversational scenarios have no expected
        // answer to compare against.
        if let gold {
            let citedFixtureIDs = result.citations.compactMap { fixtureIDs[$0.entryId] }
            sample.citedFixtureIDs = citedFixtureIDs
            sample.violations += ChatEvalScoring.goldOutcome(
                citedFixtureIDs: citedFixtureIDs,
                expected: gold.expectedEntryIDs,
                match: gold.match
            )
        }

        return sample
    }

    // MARK: - Reporting

    private static func failureDigest(_ failures: [Sample]) -> String {
        var counts: [String: Int] = [:]
        for f in failures {
            if let e = f.error { counts["error: \(e.prefix(60))", default: 0] += 1 }
            for v in f.gating { counts[v.code, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }
            .map { "  \($0.value)×  \($0.key)" }
            .joined(separator: "\n")
    }

    private static func render(_ samples: [Sample], fixtureIDs: [UUID: String], goldCount: Int) -> String {
        let passed = samples.filter(\.passed).count
        var out = "# Chat eval gate\n\n"
        out += "**\(passed)/\(samples.count) passed** "
        out += "(\(goldCount) gold questions + \(samples.count - goldCount) conversational)\n\n"

        let errored = samples.filter { $0.error != nil }
        out += "- hard failures (threw / empty): **\(errored.count)**\n"
        out += "- gate violations: **\(samples.flatMap(\.gating).count)**\n"
        let latencies = samples.filter { $0.error == nil }.map(\.seconds).sorted()
        if !latencies.isEmpty {
            let p50 = latencies[latencies.count / 2]
            let p90 = latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.9))]
            out += "- latency p50 \(String(format: "%.1f", p50))s, p90 \(String(format: "%.1f", p90))s\n"
        }

        out += "\n## Violations by code\n\n| code | count | gated |\n|---|---|---|\n"
        var byCode: [String: Int] = [:]
        for v in samples.flatMap(\.violations) { byCode[v.code, default: 0] += 1 }
        for (code, n) in byCode.sorted(by: { $0.value > $1.value }) {
            let gated = ChatEvalScoring.gating([.init(code: code, detail: "")]).isEmpty ? "reported" : "**gate**"
            out += "| `\(code)` | \(n) | \(gated) |\n"
        }
        if byCode.isEmpty { out += "| — | 0 | |\n" }

        out += "\n## By scenario\n\n| scenario | pass | n | mean chars | mean cites |\n|---|---|---|---|---|\n"
        for scenario in orderedScenarios(samples) {
            let rows = samples.filter { $0.scenario == scenario }
            let ok = rows.filter(\.passed).count
            let bodies = rows.filter { $0.error == nil }
            let chars = bodies.isEmpty ? 0 : bodies.map(\.body.count).reduce(0, +) / bodies.count
            let cites = bodies.isEmpty ? 0.0
                : Double(bodies.map(\.citations).reduce(0, +)) / Double(bodies.count)
            out += "| \(scenario) | \(ok)/\(rows.count) | \(rows.count) | \(chars) | \(String(format: "%.1f", cites)) |\n"
        }

        let failures = samples.filter { !$0.passed }
        if !failures.isEmpty {
            out += "\n## Failures\n\n"
            for f in failures.prefix(40) {
                out += "### \(f.scenario) · rep \(f.rep)\n**Q:** \(f.question)\n\n"
                if let e = f.error { out += "**ERROR:** `\(e)`\n\n" }
                for v in f.gating { out += "- `\(v.code)` — \(v.detail)\n" }
                if !f.body.isEmpty {
                    out += "\n```\n\(f.body.prefix(700))\n```\n\n"
                }
            }
            if failures.count > 40 { out += "\n_(\(failures.count - 40) more omitted)_\n" }
        }

        out += "\n## Sampled replies\n\n"
        for scenario in orderedScenarios(samples) {
            guard let s = samples.first(where: { $0.scenario == scenario && $0.error == nil }) else { continue }
            out += "**\(scenario)** — \(s.question)\n\n```\n\(s.body.prefix(600))\n```\n\n"
        }
        return out
    }

    private static func orderedScenarios(_ samples: [Sample]) -> [String] {
        var seen = Set<String>()
        return samples.map(\.scenario).filter { seen.insert($0).inserted }
    }

    // MARK: - Output

    static func outputDirectory() -> URL {
        if let path = ProcessInfo.processInfo.environment["CHAT_EVAL_OUT"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        // Repo-relative and git-ignored, so a run is reproducible from any
        // checkout rather than pointing at one session's scratchpad.
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repo.appendingPathComponent(".eval-runs")
    }

    private static func write(_ report: String, _ samples: [Sample]) {
        let dir = outputDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? report.write(to: dir.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)

        let rows: [[String: Any]] = samples.map { s in
            [
                "scenario": s.scenario,
                "question": s.question,
                "rep": s.rep,
                "corpus": s.corpus,
                "passed": s.passed,
                "error": s.error ?? "",
                "citations": s.citations,
                "chars": s.body.count,
                "seconds": s.seconds,
                "promptVersion": s.promptVersion,
                "violations": s.violations.map { ["code": $0.code, "detail": $0.detail] },
                "body": s.body
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]) {
            try? data.write(to: dir.appendingPathComponent("results.json"))
        }
    }
}
