import XCTest
@testable import withMemento

/// Spec 058 R5: the recipe rules the renderer holds by construction — one
/// question, no report opener, and a no-match lead written by Swift — and the
/// stream-stability each of them owes the bubble and TTS.
final class ReplyRendererRecipeTests: XCTestCase {

    private let leadContext = RenderContext(userTexts: [], lead: NoMatchLead.sentence)

    private func render(_ raw: String, context: RenderContext = .empty) -> RenderedReply {
        ReplyRenderer.render(raw, pack: .empty, context: context)
    }

    /// Every streamed body is where the final begins, and none is shorter than the last.
    private func assertStreamsStably(
        _ raw: String,
        context: RenderContext = .empty,
        granularity: ReplyRenderer.StreamGranularity,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let final = ReplyRenderer.render(raw, pack: .empty, context: context).body
        var previous = ""
        for end in raw.indices {
            let partial = String(raw[..<end])
            let body = ReplyRenderer.streamingBody(partial, pack: .empty, context: context, granularity: granularity)
            XCTAssertTrue(
                final.hasPrefix(body),
                "\(granularity) delta \"\(body)\" is not a prefix of \"\(final)\"",
                file: file,
                line: line
            )
            XCTAssertGreaterThanOrEqual(
                body.count,
                previous.count,
                "\(granularity) delta retracted at \"\(partial)\"",
                file: file,
                line: line
            )
            previous = body
        }
    }

    // MARK: - One question

    func test_secondQuestion_isDropped_andTheFirstCloses() {
        let rendered = render("That walk sounds like it mattered. What was that like? And what stayed with you?")
        XCTAssertEqual(rendered.body, "That walk sounds like it mattered. What was that like?")
        XCTAssertEqual(rendered.stats.droppedQuestionCount, 1)
    }

    func test_statementsAfterTheQuestion_areKept() {
        let rendered = render("What was that like? No pressure to answer.")
        XCTAssertEqual(rendered.body, "What was that like? No pressure to answer.")
        XCTAssertEqual(rendered.stats.droppedQuestionCount, 0)
    }

    func test_questionOnALaterLine_isDropped() {
        let rendered = render("The quiet came back. What changed that week?\n\nWhat else helped?")
        XCTAssertFalse(rendered.body.contains("What else helped?"))
        XCTAssertTrue(rendered.body.hasSuffix("What changed that week?"))
    }

    func test_replyWithoutAQuestion_isUntouched() {
        XCTAssertEqual(render("Take care tonight.").body, "Take care tonight.")
    }

    // MARK: - Report openers

    func test_youWroteThat_losesItsFrame_andKeepsItsContent() {
        let rendered = render("You wrote that the house was quiet. What changed?")
        XCTAssertEqual(rendered.body, "The house was quiet. What changed?")
        XCTAssertEqual(rendered.stats.strippedOpenerCount, 1)
    }

    func test_lookingAtYourEntries_isStripped() {
        let rendered = render("Looking at your entries, sleep came back in March. What helped?")
        XCTAssertEqual(rendered.body, "Sleep came back in March. What helped?")
    }

    func test_openerLaterInTheReply_isLeftAlone() {
        let raw = "That night mattered. You wrote that it was quiet. What changed?"
        XCTAssertEqual(render(raw).body, raw)
    }

    func test_openerWithoutASeam_isLeftToThePrompt() {
        let raw = "You mentioned feeling tired. What helped?"
        XCTAssertEqual(render(raw).body, raw)
    }

    // MARK: - No-match lead

    func test_lead_isPrepended_andTheModelsRestatementDropped() {
        let rendered = render(
            "You can't find an entry that supports that. What were you hoping to find in March?",
            context: leadContext
        )
        XCTAssertEqual(rendered.body, NoMatchLead.sentence + " What were you hoping to find in March?")
        XCTAssertEqual(rendered.stats.droppedLeadRestatementCount, 1)
    }

    func test_lead_closesWithAQuestion_whenTheModelWroteNothingUsable() {
        let rendered = render("{{quote:1}}", context: leadContext)
        XCTAssertEqual(rendered.body, NoMatchLead.sentence + " " + NoMatchLead.fallbackQuestion)
    }

    func test_lead_isOnScreenFromTheFirstFrame() {
        let first = ReplyRenderer.streamingBody("", pack: .empty, context: leadContext, granularity: .sentence)
        XCTAssertEqual(first, NoMatchLead.sentence)
    }

    func test_noLead_withoutAContextLead() {
        let rendered = render("I can't find an entry that supports that. What's on your mind?")
        XCTAssertEqual(rendered.body, "I can't find an entry that supports that. What's on your mind?")
        XCTAssertEqual(rendered.stats.droppedLeadRestatementCount, 0)
    }

    func test_lead_appliesOnlyToJournalChannelsOnAMiss() {
        XCTAssertTrue(NoMatchLead.applies(to: .noMatch, channel: .notebook))
        XCTAssertTrue(NoMatchLead.applies(to: .nearbyOnly, channel: .thread))
        XCTAssertFalse(NoMatchLead.applies(to: .journalGrounded, channel: .notebook))
        XCTAssertFalse(NoMatchLead.applies(to: .noMatch, channel: .companion))
    }

    // MARK: - Stream stability

    func test_recipePasses_neverRetractStreamedText() {
        let raw = "You mentioned that work was loud. What was the loudest part? And how did you get home?"
        XCTAssertEqual(render(raw).body, "Work was loud. What was the loudest part?")
        assertStreamsStably(raw, granularity: .word)
        assertStreamsStably(raw, granularity: .sentence)
    }

    func test_openerThatNeverForms_isShownOnceItCannotBecomeOne() {
        let body = ReplyRenderer.streamingBody("You finally slept. ", pack: .empty, context: .empty, granularity: .word)
        XCTAssertEqual(body, "You finally slept.")
    }

    // MARK: - Echoed turn lines

    func test_echoedMoveCue_isRemovedAtTheStart() {
        let raw = "How to reply: Answer first, then one question.\nThe walk mattered. What stayed with you?"
        XCTAssertEqual(render(raw).body, "The walk mattered. What stayed with you?")
        assertStreamsStably(raw, granularity: .word)
    }

    func test_echoedLegendAndFactsLines_areRemoved() {
        let raw = "\(EvidencePack.legendFooter)\nFacts the app computed from their journal. Narrate these.\n"
            + "The quiet came back. What changed?"
        XCTAssertEqual(render(raw).body, "The quiet came back. What changed?")
    }

    func test_howToAtTheStart_isShownOnceItDiverges() {
        let body = ReplyRenderer.streamingBody("How to put it kindly? ", pack: .empty, context: .empty, granularity: .word)
        XCTAssertEqual(body, "How to put it kindly?")
    }

    func test_leadStream_neverRetracts() {
        let raw = "You can't find an entry that supports that. What were you hoping to find? Or when?"
        assertStreamsStably(raw, context: leadContext, granularity: .sentence)
    }
}
