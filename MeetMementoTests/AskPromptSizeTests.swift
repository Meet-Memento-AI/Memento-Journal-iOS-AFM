import XCTest
@testable import MeetMemento

/// Session 6 shrink gate: `ask-core@16` + notebook suffix must be on a path
/// to ≤ 55% of the frozen `ask@15` character count (8214). Device-lane
/// `tokenCount(for:)` is the eventual proof; merge lane uses characters.
final class AskPromptSizeTests: XCTestCase {

    func test_askCorePlusNotebookSuffix_isAtMost55PercentOfAsk15() {
        let resolved = PromptRegistry.instructions(for: .ask, channel: .notebook)
        XCTAssertEqual(resolved.version, "ask-core@16")
        let limit = Int(
            (Double(PromptRegistry.ask15BaselineCharacterCount) * 0.55).rounded(.up)
        )
        XCTAssertLessThanOrEqual(
            resolved.text.count,
            limit,
            "ask-core@16 + notebook suffix is \(resolved.text.count) chars; "
                + "55% of ask@15 (\(PromptRegistry.ask15BaselineCharacterCount)) is \(limit)"
        )
    }

    func test_channelSuffixes_areAtMostSixLines() {
        for channel in [ReplyChannel.notebook, .thread, .companion, .meta, .redirect] {
            let suffix = PromptRegistry.channelSuffix(channel)
            let lines = suffix.split(separator: "\n", omittingEmptySubsequences: true)
            XCTAssertLessThanOrEqual(lines.count, 6, "\(channel)")
            XCTAssertFalse(suffix.isEmpty, "\(channel)")
        }
    }

    func test_promptExperiments_defaultToQualityPath() {
        PromptExperiments.reset()
        XCTAssertTrue(PromptExperiments.includeSchemaInPrompt)
        XCTAssertFalse(PromptExperiments.exemplarTurnEnabled)
        XCTAssertFalse(PromptExperiments.typedNotebookCap256)
    }
}
