import CryptoKit
import XCTest
@testable import withMemento

/// Golden snapshots for channel × stance × policy (clock-pinned).
final class TurnPromptGoldenSnapshotTests: XCTestCase {

    static let anchor = Date(timeIntervalSince1970: 1_781_179_200)

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    private static let policies: [ResponsePolicy?] = [nil, .answer, .reflect]

    func test_planPrompt_joinsPartsWithDoubleNewline() {
        let plan = TurnPromptGoldenFixture.plan(
            channel: .companion,
            stance: .sharing,
            policy: .reflect,
            anchor: Self.anchor,
            calendar: Self.calendar
        )
        XCTAssertEqual(plan.prompt, plan.parts.joined(separator: "\n\n"))
        XCTAssertEqual(plan.channel, .companion)
        XCTAssertNil(plan.effectiveStance)
    }

    func test_buildAskPrompt_matchesTurnPromptAssemblerAtWallClock() {
        let retrieval = TurnPromptGoldenFixture.groundedRetrieval()
        let inputs = TurnPromptGoldenFixture.standardInputs(
            channel: .notebook,
            stance: .journalGrounded,
            policy: .answer,
            retrieval: retrieval
        )
        let viaFMIS = FoundationModelsIntelligenceService.buildAskPrompt(
            question: inputs.question,
            history: inputs.history,
            retrieval: inputs.retrieval,
            stance: inputs.stance,
            shape: inputs.shape,
            archiveEmpty: inputs.archiveEmpty,
            budget: ContextBudget(window: .unavailable),
            channel: inputs.channel,
            move: inputs.move,
            policy: inputs.policy,
            evidencePack: inputs.evidencePack
        )
        let viaAssembler = TurnPromptAssembler.build(
            question: inputs.question,
            history: inputs.history,
            retrieval: inputs.retrieval,
            stance: inputs.stance,
            shape: inputs.shape,
            archiveEmpty: inputs.archiveEmpty,
            channel: inputs.channel,
            move: inputs.move,
            policy: inputs.policy,
            evidencePack: inputs.evidencePack
        )
        XCTAssertEqual(viaFMIS, viaAssembler)
    }

    func test_goldenSnapshot_companion_casual_reflect_pinnedClock() {
        let prompt = TurnPromptGoldenFixture.plan(
            channel: .companion,
            stance: .casual,
            policy: .reflect,
            anchor: Self.anchor,
            calendar: Self.calendar
        ).prompt
        XCTAssertEqual(prompt, Self.goldenCompanionCasualReflect)
        XCTAssertEqual(Self.digest(prompt), Self.goldenCompanionCasualReflectDigest)
    }

    /// Exercises channel × stance × policy under a pinned clock; fingerprints
    /// are stable for a given assembler version (regenerate with emit test).
    func test_goldenMatrix_channelStancePolicy_fingerprints() {
        var fingerprints: [String: String] = [:]
        for channel in ReplyChannel.allCases {
            let stances = channel.usesShortAssembler ? [TurnStance.casual] : TurnStance.allCases
            for stance in stances {
                for policy in Self.policies {
                    let id = TurnPromptGoldenFixture.matrixId(
                        channel: channel, stance: stance, policy: policy
                    )
                    let prompt = TurnPromptGoldenFixture.plan(
                        channel: channel,
                        stance: stance,
                        policy: policy,
                        anchor: Self.anchor,
                        calendar: Self.calendar
                    ).prompt
                    XCTAssertFalse(prompt.isEmpty, id)
                    XCTAssertTrue(prompt.contains(Self.anchorTodayLine), id)
                    XCTAssertTrue(prompt.contains("The person's latest message:"), id)
                    if let policy {
                        XCTAssertTrue(
                            prompt.contains(PromptRegistry.policySuffix(policy)),
                            id
                        )
                    }
                    if channel.usesShortAssembler {
                        XCTAssertFalse(prompt.contains(TurnStance.journalGrounded.promptLine), id)
                    }
                    let repeatBuild = TurnPromptGoldenFixture.plan(
                        channel: channel,
                        stance: stance,
                        policy: policy,
                        anchor: Self.anchor,
                        calendar: Self.calendar
                    ).prompt
                    XCTAssertEqual(prompt, repeatBuild, id)
                    fingerprints[id] = Self.digest(prompt)
                }
            }
        }
        XCTAssertEqual(fingerprints.count, TurnPromptGoldenFixture.expectedMatrixCellCount)
    }

    /// Set `EMIT_TURN_PROMPT_GOLDENS=1` on a Mac to refresh `TurnPromptGoldenFingerprints.json`.
    func test_emitFingerprintCatalog() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["EMIT_TURN_PROMPT_GOLDENS"] == "1",
            "Set EMIT_TURN_PROMPT_GOLDENS=1 to refresh fingerprints"
        )
        var catalog: [String: String] = [:]
        for channel in ReplyChannel.allCases {
            let stances = channel.usesShortAssembler ? [TurnStance.casual] : TurnStance.allCases
            for stance in stances {
                for policy in Self.policies {
                    let id = TurnPromptGoldenFixture.matrixId(
                        channel: channel, stance: stance, policy: policy
                    )
                    let prompt = TurnPromptGoldenFixture.plan(
                        channel: channel,
                        stance: stance,
                        policy: policy,
                        anchor: Self.anchor,
                        calendar: Self.calendar
                    ).prompt
                    catalog[id] = Self.digest(prompt)
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
        let url = TurnPromptGoldenFingerprintCatalog.fixtureURL
        try data.write(to: url)
        print("Wrote \(catalog.count) fingerprints to \(url.path)")
    }

    private static func digest(_ text: String) -> String {
        let hash = SHA256.hash(data: Data(text.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static let anchorTodayLine = "Today is Thursday, June 11, 2026."

    private static let goldenCompanionCasualReflect = """
How to reply: Show you heard the specific thing they said; one question about that.

Today is Thursday, June 11, 2026.

The person's latest message: hello there

Reflect: at most one concrete detail from their latest message, then one question.
"""

    private static let goldenCompanionCasualReflectDigest =
        "7defd90ff023d3b98445273156634a5776a3a6e71fd32e1000ebc7c0d5409766"
}

// MARK: - Fixture

private enum TurnPromptGoldenFixture {

    static let expectedMatrixCellCount = 66

    static func matrixId(channel: ReplyChannel, stance: TurnStance, policy: ResponsePolicy?) -> String {
        let policyKey = policy?.rawValue ?? "none"
        return "\(channel.rawValue)_\(stance.rawValue)_\(policyKey)"
    }

    static func groundedRetrieval() -> RetrievalResult {
        let entries = [
            RetrievedEntry(
                ref: 1, id: UUID(), date: Date(timeIntervalSince1970: 1_772_539_200),
                text: "Slept through the night for the first time in weeks. The house was quiet."
            ),
            RetrievedEntry(
                ref: 2, id: UUID(), date: Date(timeIntervalSince1970: 1_773_057_600),
                text: "Work was loud again today and I left with my jaw still tight."
            )
        ]
        return RetrievalResult(
            entries: entries,
            contextBlock: EntryRetriever.contextBlock(for: entries, ambient: false),
            isAmbient: false
        )
    }

    static func standardInputs(
        channel: ReplyChannel,
        stance: TurnStance,
        policy: ResponsePolicy?,
        retrieval: RetrievalResult = .empty
    ) -> (
        question: String,
        history: [ChatTurn],
        retrieval: RetrievalResult,
        stance: TurnStance,
        shape: RecallTurnShape,
        archiveEmpty: Bool,
        channel: ReplyChannel,
        move: ConversationalMove?,
        policy: ResponsePolicy?,
        evidencePack: EvidencePack?
    ) {
        let question = channel.usesShortAssembler ? "hello there" : "How have I been sleeping?"
        let move: ConversationalMove? = channel.usesShortAssembler ? .reflectAndAsk : .patternThenAsk
        let pack = channel.allowsRetrieval && !channel.usesShortAssembler
            ? EvidencePackBuilder.build(
                retrieval: retrieval, stance: stance, channel: channel, archiveEmpty: false
            )
            : nil
        return (
            question: question,
            history: [],
            retrieval: retrieval,
            stance: stance,
            shape: .answerOpen,
            archiveEmpty: false,
            channel: channel,
            move: move,
            policy: policy,
            evidencePack: pack
        )
    }

    static func plan(
        channel: ReplyChannel,
        stance: TurnStance,
        policy: ResponsePolicy?,
        anchor: Date,
        calendar: Calendar
    ) -> TurnPromptPlan {
        let retrieval = channel.usesShortAssembler ? .empty : groundedRetrieval()
        let inputs = standardInputs(
            channel: channel, stance: stance, policy: policy, retrieval: retrieval
        )
        return TurnPromptAssembler.plan(
            question: inputs.question,
            history: inputs.history,
            retrieval: inputs.retrieval,
            stance: inputs.stance,
            shape: inputs.shape,
            archiveEmpty: inputs.archiveEmpty,
            channel: inputs.channel,
            move: inputs.move,
            policy: inputs.policy,
            evidencePack: inputs.evidencePack,
            now: anchor,
            calendar: calendar
        )
    }
}

private enum TurnPromptGoldenFingerprintCatalog {
    static var fixtureURL: URL {
        Bundle(for: TurnPromptGoldenSnapshotTests.self)
            .bundleURL
            .appendingPathComponent("Fixtures/TurnPromptGolden/TurnPromptGoldenFingerprints.json")
    }
}
