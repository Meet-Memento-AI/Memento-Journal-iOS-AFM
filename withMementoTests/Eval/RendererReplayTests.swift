import XCTest
@testable import withMemento

/// T2 / MEM-324 — renderer replay gate (ask-chat 100 plan §1).
///
/// Study VI turns are re-scored mechanically; aggregate gating counts must match
/// `Fixtures/replay/baseline-violation-counts.json`. `raw-samples.json` runs
/// pre-render model text through `ReplyRenderer.render` on every PR.
///
/// Until T1 records `rawBody` on synthetic runs, the Study VI corpus is
/// rendered-surface only (see `Fixtures/replay/README.md`).
final class RendererReplayTests: XCTestCase {

    private struct ReplayManifest: Decodable {
        let sourceJSONL: String
        let turnCount: Int
        let renderedOnly: Bool

        enum CodingKeys: String, CodingKey {
            case sourceJSONL = "source_jsonl"
            case turnCount = "turn_count"
            case renderedOnly = "rendered_only"
        }
    }

    private struct ReplayBaseline: Decodable {
        let turnCount: Int
        let renderedOnly: Bool
        let gatingCounts: [String: Int]
        let gatingTotal: Int

        enum CodingKeys: String, CodingKey {
            case turnCount = "turn_count"
            case renderedOnly = "rendered_only"
            case gatingCounts = "gating_counts"
            case gatingTotal = "gating_total"
        }
    }

    private struct ReplayTurn: Decodable {
        let id: String
        let arm: String?
        let channel: String?
        let turnType: String?
        let responsePolicy: String?
        let evidenceState: String?
        let promptVersion: String?
        let body: String
        let rawBody: String?
        let archivedGating: [String]?
        let citations: [ReplayCitation]?
        let facts: [InsightFact]?

        enum CodingKeys: String, CodingKey {
            case id, arm, channel, body, citations, facts
            case turnType = "turn_type"
            case responsePolicy = "response_policy"
            case evidenceState = "evidence_state"
            case promptVersion = "prompt_version"
            case rawBody
            case archivedGating = "archived_gating"
        }
    }

    private struct ReplayCitation: Decodable {
        let entryUUID: String
        let entryCreatedAt: String?
        let excerpt: String

        enum CodingKeys: String, CodingKey {
            case entryUUID = "entry_uuid"
            case entryCreatedAt = "entry_created_at"
            case excerpt
        }
    }

    private struct RawSample: Decodable {
        let label: String
        let rawBody: String
        let packState: String
        let context: RawContext?

        struct RawContext: Decodable {
            let userTexts: [String]
            let lead: String?
        }
    }

    private static let iso = ISO8601DateFormatter()

    // MARK: - Paths

    private static func replayDirectory() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["RENDERER_REPLAY_FIXTURES"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let testsRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return testsRoot.appendingPathComponent("Fixtures/replay")
    }

    private static func loadTurns() throws -> [ReplayTurn] {
        let url = try replayDirectory().appendingPathComponent("study-vi-turns.jsonl")
        let text = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        var turns: [ReplayTurn] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            turns.append(try decoder.decode(ReplayTurn.self, from: Data(line.utf8)))
        }
        return turns
    }

    // MARK: - Study VI re-score

    func test_studyVI_gatingCounts_matchBaseline() throws {
        let dir = try Self.replayDirectory()
        let baseline = try JSONDecoder().decode(
            ReplayBaseline.self,
            from: Data(contentsOf: dir.appendingPathComponent("baseline-violation-counts.json"))
        )
        let manifest = try JSONDecoder().decode(
            ReplayManifest.self,
            from: Data(contentsOf: dir.appendingPathComponent("manifest.json"))
        )
        XCTAssertTrue(manifest.renderedOnly, "remove rendered_only gate when T1 lands rawBody")
        XCTAssertFalse(manifest.sourceJSONL.isEmpty)
        XCTAssertEqual(manifest.turnCount, baseline.turnCount)
        XCTAssertTrue(baseline.renderedOnly)

        let (personaEntries, _) = try ChatEvalCorpus.personaCorpus()
        let personaIndex = ChatEvalScoring.QuoteIndex(personaEntries)
        let emptyIndex = ChatEvalScoring.QuoteIndex([])

        var counts: [String: Int] = [:]
        var mismatches = 0
        for turn in try Self.loadTurns() {
            let scored = Self.score(turn: turn, personaIndex: personaIndex, emptyIndex: emptyIndex)
            let gating = ChatEvalScoring.gating(scored).map(\.code).sorted()
            if let archived = turn.archivedGating?.sorted(), archived != gating {
                mismatches += 1
            }
            for code in gating {
                counts[code, default: 0] += 1
            }
        }

        XCTAssertEqual(
            mismatches, 0,
            "Swift scorer drifted from archived Study VI gating on \(mismatches) turns. "
            + "Re-run REGEN_RENDERER_REPLAY_BASELINE=1 on RendererReplayTests/test_regenerateRendererReplayBaseline."
        )
        XCTAssertEqual(counts, baseline.gatingCounts)
        XCTAssertEqual(counts.values.reduce(0, +), baseline.gatingTotal)
    }

    func test_regenerateRendererReplayBaseline() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            env["REGEN_RENDERER_REPLAY_BASELINE"] == "1",
            "set REGEN_RENDERER_REPLAY_BASELINE=1 to rewrite replay baselines"
        )

        let dir = try Self.replayDirectory()
        let turnsURL = dir.appendingPathComponent("study-vi-turns.jsonl")
        let (personaEntries, _) = try ChatEvalCorpus.personaCorpus()
        let personaIndex = ChatEvalScoring.QuoteIndex(personaEntries)
        let emptyIndex = ChatEvalScoring.QuoteIndex([])

        var counts: [String: Int] = [:]
        var lines: [String] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for turn in try Self.loadTurns() {
            let scored = Self.score(turn: turn, personaIndex: personaIndex, emptyIndex: emptyIndex)
            let gating = ChatEvalScoring.gating(scored).map(\.code).sorted()
            for code in gating { counts[code, default: 0] += 1 }

            var payload: [String: Any] = [
                "id": turn.id,
                "arm": turn.arm as Any,
                "channel": turn.channel as Any,
                "turn_type": turn.turnType as Any,
                "response_policy": turn.responsePolicy as Any,
                "evidence_state": turn.evidenceState as Any,
                "prompt_version": turn.promptVersion as Any,
                "body": turn.body,
                "archived_gating": gating
            ]
            if let raw = turn.rawBody { payload["rawBody"] = raw }
            if let citations = turn.citations {
                payload["citations"] = citations.map {
                    [
                        "entry_uuid": $0.entryUUID,
                        "entry_created_at": $0.entryCreatedAt as Any,
                        "excerpt": $0.excerpt
                    ]
                }
            }
            if let facts = turn.facts,
               let data = try? encoder.encode(facts),
               let decoded = try? JSONSerialization.jsonObject(with: data) {
                payload["facts"] = decoded
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            lines.append(String(data: data, encoding: .utf8)!)
        }

        try lines.joined(separator: "\n").appending("\n").write(to: turnsURL, atomically: true, encoding: .utf8)

        let baseline: [String: Any] = [
            "turn_count": lines.count,
            "rendered_only": !lines.contains("\"rawBody\""),
            "gating_counts": counts,
            "gating_total": counts.values.reduce(0, +)
        ]
        let baselineData = try JSONSerialization.data(withJSONObject: baseline, options: [.prettyPrinted, .sortedKeys])
        try baselineData.write(to: dir.appendingPathComponent("baseline-violation-counts.json"))
        XCTFail("Baseline regenerated — commit Fixtures/replay and re-run without REGEN.")
    }

    // MARK: - Raw renderer replay

    func test_rawSamples_renderWithoutNewGatingViolations() throws {
        let url = try Self.replayDirectory().appendingPathComponent("raw-samples.json")
        let samples = try JSONDecoder().decode([RawSample].self, from: Data(contentsOf: url))
        let emptyIndex = ChatEvalScoring.QuoteIndex([])

        for sample in samples {
            let state = EvidenceState(rawValue: sample.packState) ?? .none
            let pack = EvidencePack.unquotable(state, dates: [], wasEmpty: state == .none, wasAmbient: state == .ambient)
            let ctx = RenderContext(
                userTexts: sample.context?.userTexts ?? [],
                lead: sample.context?.lead
            )
            let rendered = ReplyRenderer.render(sample.rawBody, pack: pack, context: ctx)
            let violations = ChatEvalScoring.scoreGeneratedReply(
                body: rendered.body,
                isCasual: false,
                quoteIndex: emptyIndex,
                citations: [],
                facts: [],
                capTokens: ReplyChannel.companion.maximumResponseTokens(retrievalRan: false),
                openRequired: true
            )
            XCTAssertTrue(
                ChatEvalScoring.gating(violations).isEmpty,
                "\(sample.label): \(violations)"
            )
            XCTAssertFalse(rendered.body.contains("{{"), sample.label)
        }
    }

    // MARK: - Scoring

    private static func score(
        turn: ReplayTurn,
        personaIndex: ChatEvalScoring.QuoteIndex,
        emptyIndex: ChatEvalScoring.QuoteIndex
    ) -> [ChatEvalScoring.Violation] {
        let index = turn.arm == "empty" ? emptyIndex : personaIndex
        let turnType = TurnType(rawValue: turn.turnType ?? "") ?? .journalQuery
        let isCasual = turnType == .social || turnType == .acknowledgement
        let channel = ReplyChannel(rawValue: turn.channel ?? "") ?? .notebook
        let policy = ResponsePolicy(rawValue: turn.responsePolicy ?? "") ?? .answer
        let citations = decodeCitations(turn.citations ?? [])
        let retrievalRan = !citations.isEmpty
        let cap = channel.maximumResponseTokens(retrievalRan: retrievalRan)
        let bodyEmpty = turn.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let openRequired = ResponsePolicyResolver.openRequired(
            policy: policy,
            bodyIsEmpty: bodyEmpty || turn.promptVersion == "insight-fact@1"
        )
        return ChatEvalScoring.scoreGeneratedReply(
            body: turn.body,
            isCasual: isCasual,
            quoteIndex: index,
            citations: citations,
            facts: turn.facts ?? [],
            capTokens: cap,
            openRequired: openRequired
        )
    }

    private static func decodeCitations(_ rows: [ReplayCitation]) -> [AskCitation] {
        rows.compactMap { row in
            guard let uuid = UUID(uuidString: row.entryUUID) else { return nil }
            let date = row.entryCreatedAt.flatMap { iso.date(from: $0) } ?? Date()
            return AskCitation(entryId: uuid, entryDate: date, excerpt: row.excerpt)
        }
    }
}
