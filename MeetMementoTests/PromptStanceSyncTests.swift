import XCTest
@testable import MeetMemento

/// Keeps the stance contract from drifting: every TurnStance tag that
/// RetrievalPolicy can emit must be explained in the ask prompt, and the
/// prompt versions must reflect the turn-architecture pass.
final class PromptStanceSyncTests: XCTestCase {

    func test_everyStanceTag_appearsInAskPrompt() {
        let prompt = PromptRegistry.instructions(for: .ask).text
        for stance in TurnStance.allCases {
            XCTAssertTrue(
                prompt.contains(stance.tagPrefix),
                "ask prompt is missing the stance contract for \(stance.tagPrefix)"
            )
        }
    }

    func test_degradedPrompt_mentionsTurnTags() {
        let prompt = PromptRegistry.instructions(for: .ask, degraded: true).text
        XCTAssertTrue(prompt.contains("[Turn:"))
    }

    func test_promptVersions() {
        XCTAssertEqual(PromptRegistry.instructions(for: .ask).version, "ask@3")
        XCTAssertEqual(PromptRegistry.instructions(for: .ask, degraded: true).version, "ask-degraded@3")
        XCTAssertEqual(PromptRegistry.instructions(for: .summary).version, "summarize@1")
    }

    func test_askPrompt_hasAntiTemplateRule() {
        let prompt = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(prompt.contains("Never open a reply with \"You wrote\""))
    }

    func test_stancePromptLines_areBracketedSingleLines() {
        for stance in TurnStance.allCases {
            XCTAssertTrue(stance.promptLine.hasPrefix("[Turn: "), "\(stance)")
            XCTAssertTrue(stance.promptLine.hasSuffix("]"), "\(stance)")
            XCTAssertFalse(stance.promptLine.contains("\n"), "\(stance)")
        }
    }
}
