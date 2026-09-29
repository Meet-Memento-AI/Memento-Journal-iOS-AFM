import XCTest
@testable import withMemento

/// Keeps the stance contract from drifting (058): stance rules are chosen in
/// Swift and ride a plain-prose turn line; instructions carry no stance menu,
/// no marker grammar, and no bracketed tag vocabulary for the model to echo.
final class PromptStanceSyncTests: XCTestCase {

    private static let tagVocabulary = [
        "[Turn:", "[Shape:", "[Evidence", "[Name:", "[Safety:", "[Move:", "[Today:",
        "[Computed]", "[Spoken:", "[Don't", "[They are"
    ]

    private static let markerGrammar = ["{{quote:", "{{date:"]

    /// Every instruction set the Ask path can resolve.
    private var askInstructions: [String: String] {
        var surfaces: [String: String] = [:]
        for channel in ReplyChannel.allCases {
            for degraded in [false, true] {
                surfaces["\(channel) degraded=\(degraded)"] =
                    PromptRegistry.instructions(for: .ask, degraded: degraded, channel: channel).text
            }
        }
        return surfaces
    }

    func test_channelSuffixes_carryNoStanceMenu() {
        for channel in ReplyChannel.allCases {
            for degraded in [false, true] {
                let suffix = PromptRegistry.channelSuffix(channel, degraded: degraded)
                for stance in PromptRegistry.suffixStances(for: channel) {
                    XCTAssertFalse(suffix.contains(stance.label),
                                   "\(channel) suffix restates the \(stance) turn line")
                }
                let lines = suffix.split(separator: "\n", omittingEmptySubsequences: true)
                XCTAssertLessThanOrEqual(lines.count, 6, "\(channel) suffix exceeds 6 lines")
            }
        }
        let light = PromptRegistry.instructions(for: .ask, channel: .phatic).text
        XCTAssertTrue(light.contains("one genuine question"))
    }

    /// The model mirrors tag syntax as output format; Study VI saw `[Evidence]`
    /// echoed 25 times. Nothing it reads may use it.
    func test_noModelFacingSurface_usesBracketedTags() {
        var surfaces = askInstructions
        surfaces["AskAnswerGuides.body"] = AskAnswerGuides.body
        surfaces["LightAskAnswerGuides.body"] = LightAskAnswerGuides.body
        for stance in TurnStance.allCases {
            surfaces["stance \(stance)"] = stance.promptLine
        }
        surfaces["legend header"] = EvidencePack.legendHeader
        surfaces["ambient note"] = EvidencePack.ambientNote
        surfaces["none note"] = EvidencePack.noneNote
        surfaces["spoken line"] = PromptRegistry.spokenTurnShapeLine
        surfaces["name skip"] = PromptPersonalization.nameSkipLine
        surfaces["today"] = FoundationModelsIntelligenceService.todayLine()
        surfaces["no-match lead"] = NoMatchLead.promptLine
        for (name, text) in surfaces {
            for tag in Self.tagVocabulary {
                XCTAssertFalse(text.contains(tag), "\(name) still uses \(tag)")
            }
        }
    }

    /// The marker grammar is taught only by the matched legend, so a turn with
    /// nothing to place has no grammar to misuse (055 R1's open item).
    func test_instructionsAndStanceLines_neverTeachTheMarkerGrammar() {
        var surfaces = askInstructions
        surfaces["AskAnswerGuides.body"] = AskAnswerGuides.body
        for stance in TurnStance.allCases {
            surfaces["stance \(stance)"] = stance.promptLine
        }
        surfaces["ambient note"] = EvidencePack.ambientNote
        surfaces["none note"] = EvidencePack.noneNote
        for (name, text) in surfaces {
            for marker in Self.markerGrammar {
                XCTAssertFalse(text.contains(marker), "\(name) teaches \(marker)")
            }
        }
        XCTAssertTrue(EvidencePack.legendFooter.contains("{{date:N}}"))
        XCTAssertTrue(EvidencePack.legendFooter.contains("{{quote:N}}"))
    }

    func test_promptVersions() {
        XCTAssertEqual(PromptRegistry.instructions(for: .ask).version, "ask-core@20")
        XCTAssertEqual(PromptRegistry.instructions(for: .ask, degraded: true).version, "ask-degraded@20")
        XCTAssertEqual(PromptRegistry.instructions(for: .summary).version, "summarize@2")
    }

    /// Spec 050: no surface the model reads may still grant italics as the
    /// vehicle for a journal quote, or ask it to reproduce a quoted field.
    func test_noPromptSurface_grantsItalicQuotes() {
        let retired = [
            "italic exact quote", "italics for exact journal quotes", "italic quote",
            "exact quote in *italics*", "italics for an exact journal quote",
            "reproduce any quoted field exactly"
        ]
        var surfaces = askInstructions
        surfaces["AskAnswerGuides.body"] = AskAnswerGuides.body
        for stance in TurnStance.allCases {
            surfaces["stance \(stance)"] = stance.promptLine
        }
        for (name, text) in surfaces {
            for phrase in retired {
                XCTAssertFalse(text.contains(phrase), "\(name) still says \"\(phrase)\"")
            }
        }
    }

    func test_askPrompt_opensWithRoleAndDomainPermission() {
        let prompt = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(prompt.hasPrefix("You are Memento, a journaling companion."))
        XCTAssertTrue(prompt.contains("You can talk about anything"))
    }

    func test_askPrompt_hasAntiTemplateHardBans() {
        let prompt = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(prompt.contains("Never open with \"You wrote\""))
        XCTAssertTrue(prompt.contains("Looking at your entries"))
        XCTAssertTrue(prompt.contains("In your journal"))
        XCTAssertFalse(prompt.contains("(\"you wrote"))
        XCTAssertFalse(prompt.contains("\"you mentioned"))
    }

    func test_askPrompt_isConversationNotReport() {
        let prompt = PromptRegistry.instructions(for: .ask).text
        XCTAssertTrue(prompt.contains("conversation, not a report"))
        XCTAssertTrue(prompt.contains("Meet them"))
        XCTAssertTrue(prompt.contains("stay with that one moment"))
        XCTAssertFalse(prompt.contains("names a pattern"))
        XCTAssertFalse(prompt.contains("Follow it exactly"))
        XCTAssertFalse(prompt.contains("answer and stop"))
        XCTAssertFalse(prompt.contains("Meet them only"))
        XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not skip continuers"))
        XCTAssertTrue(prompt.contains("what they just said"))
    }

    func test_stancePromptLines_arePlainSingleLines() {
        for stance in TurnStance.allCases {
            let line = stance.promptLine
            XCTAssertFalse(line.hasPrefix("["), "\(stance)")
            XCTAssertFalse(line.contains("\n"), "\(stance)")
            XCTAssertTrue(line.hasSuffix("."), "\(stance)")
            XCTAssertTrue(line.hasPrefix(stance.label), "\(stance)")
        }
    }

    func test_journalGroundedStance_describesPiecesNotBrevity() {
        let line = TurnStance.journalGrounded.promptLine
        XCTAssertTrue(line.contains("Meet them"))
        XCTAssertTrue(line.contains("stay with that moment"))
        XCTAssertTrue(line.contains("then ask one question"))
        XCTAssertTrue(line.contains("journal moments"))
        XCTAssertFalse(line.contains("pattern"))
        XCTAssertFalse(line.contains("italic"))
        XCTAssertFalse(line.contains("Open only if"))
        XCTAssertFalse(line.contains("answer and stop"))
        XCTAssertTrue(TurnStance.followupThread.promptLine.contains("entry inventory"))
        XCTAssertTrue(TurnStance.followupThread.promptLine.contains("new heading"))
    }

    func test_casualStance_isNotALengthQuota() {
        let line = TurnStance.casual.promptLine
        XCTAssertTrue(line.contains("Meet them"))
        XCTAssertTrue(line.contains("No headings or lists"))
        XCTAssertTrue(line.contains("then ask one question"))
        XCTAssertFalse(line.contains("one or two friendly sentences"))
        XCTAssertFalse(line.contains("answer and stop"))
        XCTAssertFalse(line.contains("Meet them only"))
    }

    func test_sharingStance_doesNotForceANotebookPage() {
        let line = TurnStance.sharing.promptLine
        XCTAssertTrue(line.contains("Follow what they said"))
        XCTAssertTrue(line.contains("No ### unless they asked for the journal"))
        XCTAssertTrue(line.contains("then ask one question"))
        XCTAssertEqual(TurnStance.sharing.label, "They are sharing something.")
    }

    /// The no-match sentence is Swift's to write (`NoMatchLead`); the turn
    /// line never quotes it, so there is nothing to transcribe.
    func test_noMatchStance_isDirectEmptyRecall() {
        let line = TurnStance.noMatch.promptLine
        XCTAssertFalse(line.contains(NoMatchLead.sentence))
        XCTAssertFalse(NoMatchLead.promptLine.contains(NoMatchLead.sentence))
        XCTAssertTrue(line.contains("Do not invent"))
        XCTAssertTrue(line.contains("change the subject"))
        XCTAssertTrue(line.contains("No heading, no list"))
        XCTAssertFalse(line.contains("invite them to write about it"))
        XCTAssertFalse(line.contains("answer and stop"))
    }

    func test_localeLine_isApplesExactPhrase_outsideUSEnglish() {
        XCTAssertNil(PromptRegistry.localeLine(for: Locale(identifier: "en_US")))
        XCTAssertEqual(PromptRegistry.localeLine(for: Locale(identifier: "en_GB")),
                       "The person's locale is en_GB.")
        XCTAssertEqual(PromptRegistry.localeLine(for: Locale(identifier: "es_MX")),
                       "The person's locale is es_MX.")
        let spanish = PromptRegistry.instructions(for: .ask, locale: Locale(identifier: "es_MX"))
        XCTAssertTrue(spanish.text.hasPrefix("The person's locale is es_MX.\n\nYou are Memento"))
        XCTAssertEqual(spanish.version, "ask-core@20+loc")
    }
}
