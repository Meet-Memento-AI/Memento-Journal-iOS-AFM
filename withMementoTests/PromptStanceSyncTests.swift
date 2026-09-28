import XCTest
@testable import withMemento

/// Keeps the stance contract from drifting: every TurnStance tag that
/// RetrievalPolicy can emit must be explained in the ask prompt, and the
/// prompt versions must reflect the turn-architecture pass.
final class PromptStanceSyncTests: XCTestCase {

    func test_eachAskChannelSuffix_listsItsStances() {
        let askSuffixChannels: [ReplyChannel] = [
            .notebook, .thread, .companion, .meta, .redirect
        ]
        for channel in askSuffixChannels {
            let suffix = PromptRegistry.channelSuffix(channel)
            for stance in PromptRegistry.suffixStances(for: channel) {
                XCTAssertTrue(
                    suffix.contains(stance.tagPrefix),
                    "\(channel) suffix is missing \(stance.tagPrefix)"
                )
            }
            let lines = suffix.split(separator: "\n", omittingEmptySubsequences: true)
            XCTAssertLessThanOrEqual(lines.count, 6, "\(channel) suffix exceeds 6 lines")
        }
        let light = PromptRegistry.instructions(for: .ask, channel: .phatic).text
        XCTAssertTrue(light.contains("one genuine question") || light.contains("[Turn:"))
    }

    func test_askCore_doesNotListTheStanceMenu() {
        let core = PromptRegistry.instructions(for: .ask, channel: .notebook).text
        // Core + notebook suffix still mentions journal-question tags, but
        // casual lives only on chat-light.
        XCTAssertFalse(core.contains(TurnStance.casual.tagPrefix))
        XCTAssertFalse(core.contains(TurnStance.aboutApp.tagPrefix))
        XCTAssertFalse(core.contains(TurnStance.outsideScope.tagPrefix))
        XCTAssertFalse(core.contains(TurnStance.sharing.tagPrefix))
    }

    func test_degradedPrompt_mentionsTurnTags() {
        let prompt = PromptRegistry.instructions(for: .ask, degraded: true).text
        XCTAssertTrue(prompt.contains("[Turn:"))
    }

    func test_promptVersions() {
        XCTAssertEqual(PromptRegistry.instructions(for: .ask).version, "ask-core@19")
        XCTAssertEqual(PromptRegistry.instructions(for: .ask, degraded: true).version, "ask-degraded@19")
        XCTAssertEqual(PromptRegistry.instructions(for: .summary).version, "summarize@2")
    }

    /// Spec 050: every channel that can carry an [Evidence] list states the
    /// marker rule, in the full and the degraded suffix.
    func test_retrievingChannelSuffixes_stateTheMarkerContract() {
        for channel in ReplyChannel.allCases where channel.allowsRetrieval {
            for degraded in [false, true] {
                let suffix = PromptRegistry.channelSuffix(channel, degraded: degraded)
                XCTAssertTrue(suffix.contains("{{quote:N}}"), "\(channel) degraded=\(degraded)")
                XCTAssertTrue(suffix.contains("{{date:N}}"), "\(channel) degraded=\(degraded)")
                let lines = suffix.split(separator: "\n", omittingEmptySubsequences: true)
                XCTAssertLessThanOrEqual(lines.count, 6, "\(channel) degraded=\(degraded)")
            }
        }
        for stance in [TurnStance.journalGrounded, .followupThread] {
            XCTAssertTrue(stance.promptLine.contains("{{quote:N}}"), "\(stance)")
            XCTAssertTrue(stance.promptLine.contains("[Evidence]"), "\(stance)")
        }
    }

    /// Spec 050: no surface the model reads may still grant italics as the
    /// vehicle for a journal quote, or ask it to reproduce a quoted field.
    func test_noPromptSurface_grantsItalicQuotes() {
        let retired = [
            "italic exact quote", "italics for exact journal quotes", "italic quote",
            "exact quote in *italics*", "italics for an exact journal quote",
            "reproduce any quoted field exactly"
        ]
        var surfaces: [String: String] = ["AskAnswerGuides.body": AskAnswerGuides.body]
        for channel in ReplyChannel.allCases {
            for degraded in [false, true] {
                surfaces["\(channel) degraded=\(degraded)"] =
                    PromptRegistry.instructions(for: .ask, degraded: degraded, channel: channel).text
            }
        }
        for stance in TurnStance.allCases {
            surfaces["stance \(stance)"] = stance.promptLine
        }
        for (name, text) in surfaces {
            for phrase in retired {
                XCTAssertFalse(text.contains(phrase), "\(name) still says \"\(phrase)\"")
            }
        }
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
        // Sentence-initial in askCore; see AskPromptContractTests.
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not skip continuers"))
        XCTAssertTrue(
            prompt.contains("what they just said") || prompt.contains("how they are")
        )
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
        XCTAssertTrue(line.contains("{{date:N}}"))
        XCTAssertTrue(line.contains("{{quote:N}}"))
        XCTAssertFalse(line.contains("italic"))
        XCTAssertTrue(line.contains("never type a quote or date yourself"))
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
        XCTAssertTrue(line.contains("can't find an entry that supports that"))
        XCTAssertTrue(line.contains("do not invent"))
        XCTAssertTrue(line.contains("do not change the subject"))
        XCTAssertTrue(line.contains("no heading, no list"))
        XCTAssertFalse(line.contains("invite them to write about it"))
        XCTAssertFalse(line.contains("answer and stop"))
    }
}
