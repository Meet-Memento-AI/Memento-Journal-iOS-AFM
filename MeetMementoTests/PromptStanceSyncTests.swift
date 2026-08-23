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
        XCTAssertEqual(PromptRegistry.instructions(for: .ask).version, "ask@14")
        XCTAssertEqual(PromptRegistry.instructions(for: .ask, degraded: true).version, "ask-degraded@14")
        XCTAssertEqual(PromptRegistry.instructions(for: .summary).version, "summarize@1")
    }

    func test_askPrompt_hasAntiTemplateHardBans() {
        let prompt = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(prompt.contains("Never open a reply with \"You wrote\""))
        XCTAssertTrue(prompt.contains("Looking at your entries"))
        XCTAssertTrue(prompt.contains("In your journal"))
        // Conflicting voice examples must stay gone (ask@3 taught these).
        XCTAssertFalse(prompt.contains("(\"you wrote"))
        XCTAssertFalse(prompt.contains("\"you mentioned"))
    }

    func test_askPrompt_isConversationNotReport() {
        let prompt = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(prompt.contains("conversation, not a report"))
        XCTAssertTrue(prompt.contains("Meet them"))
        XCTAssertTrue(prompt.contains("one notebook moment")
            || prompt.contains("one dated moment")
            || prompt.contains("one ### notebook moment"))
        XCTAssertFalse(prompt.contains("Follow it exactly"))
        XCTAssertFalse(prompt.contains("answer and stop"))
        XCTAssertFalse(prompt.contains("Meet them only"))
        XCTAssertTrue(prompt.contains("do not skip continuers"))
        XCTAssertTrue(prompt.contains("how they are"))
    }

    func test_stancePromptLines_areBracketedSingleLines() {
        for stance in TurnStance.allCases {
            XCTAssertTrue(stance.promptLine.hasPrefix("[Turn: "), "\(stance)")
            XCTAssertTrue(stance.promptLine.hasSuffix("]"), "\(stance)")
            XCTAssertFalse(stance.promptLine.contains("\n"), "\(stance)")
        }
    }

    func test_journalGroundedStance_describesPiecesNotBrevity() {
        let line = TurnStance.journalGrounded.promptLine
        XCTAssertTrue(line.contains("Meet them"))
        XCTAssertTrue(line.contains("Sit"))
        XCTAssertTrue(line.contains("then one question"))
        XCTAssertTrue(line.contains("pattern from the evidence"))
        XCTAssertTrue(line.contains("###"))
        XCTAssertTrue(line.contains("italic exact quote"))
        XCTAssertFalse(line.contains("Open only if"))
        XCTAssertFalse(line.contains("answer and stop"))
        XCTAssertTrue(TurnStance.followupThread.promptLine.contains("entry inventory"))
        XCTAssertTrue(TurnStance.followupThread.promptLine.contains("new heading"))
    }

    func test_casualStance_isNotALengthQuota() {
        let line = TurnStance.casual.promptLine
        XCTAssertTrue(line.contains("Meet them"))
        XCTAssertTrue(line.contains("no headings or lists"))
        XCTAssertTrue(line.contains("then one question"))
        XCTAssertFalse(line.contains("one or two friendly sentences"))
        XCTAssertFalse(line.contains("answer and stop"))
        XCTAssertFalse(line.contains("Meet them only"))
    }

    func test_sharingStance_doesNotForceANotebookPage() {
        let line = TurnStance.sharing.promptLine
        XCTAssertTrue(line.contains("follow what they said"))
        XCTAssertTrue(line.contains("no ### unless they asked for the journal"))
        XCTAssertTrue(line.contains("then one question"))
        XCTAssertEqual(line.components(separatedBy: " — ").first, "[Turn: sharing")
    }

    func test_noMatchStance_isDirectEmptyRecall() {
        let line = TurnStance.noMatch.promptLine
        XCTAssertTrue(line.contains("don't see anything from that stretch"))
        XCTAssertTrue(line.contains("do not invent"))
        XCTAssertTrue(line.contains("do not change the subject"))
        XCTAssertTrue(line.contains("no heading, no list"))
        XCTAssertFalse(line.contains("invite them to write about it"))
        XCTAssertFalse(line.contains("answer and stop"))
    }
}
