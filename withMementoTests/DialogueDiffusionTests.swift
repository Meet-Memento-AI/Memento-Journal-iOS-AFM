import XCTest
@testable import MeetMemento

/// Spec 050. The closed-form reverse step of dialogue diffusion.
/// No model: a clean reply is returned unchanged, a surplus question is
/// deleted, and a semantic miss is named for a later infill.
final class DialogueDiffusionTests: XCTestCase {

    func test_cleanGoodbyeIsUntouched() {
        let body = "Goodnight.\nSleep well."
        let result = DialogueDiffusion.denoise(
            body: body, policy: .acknowledge, userTurn: "goodnight"
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.applied.isEmpty)
        XCTAssertTrue(result.infill.isEmpty)
    }

    func test_acknowledgeDropsTheQuestionAndKeepsTheClose() {
        let result = DialogueDiffusion.denoise(
            body: "Goodnight. What are you holding onto?",
            policy: .acknowledge,
            userTurn: "goodbye"
        )
        XCTAssertEqual(result.body, "Goodnight.")
        XCTAssertEqual(result.applied, ["dialogue.questionOnAcknowledge"])
        XCTAssertTrue(result.infill.isEmpty)
        let again = DialogueDiffusion.denoise(
            body: result.body, policy: .acknowledge, userTurn: "goodbye"
        )
        XCTAssertEqual(again.body, result.body)
        XCTAssertTrue(again.applied.isEmpty)
        XCTAssertTrue(again.infill.isEmpty)
    }

    func test_acknowledgeFlattensAGoodbyeMarkWithoutAskingForARewrite() {
        let result = DialogueDiffusion.denoise(
            body: "Goodnight?",
            policy: .acknowledge,
            userTurn: "goodnight"
        )
        XCTAssertEqual(result.body, "Goodnight.")
        XCTAssertEqual(result.applied, ["dialogue.questionOnAcknowledge"])
        XCTAssertTrue(result.infill.isEmpty)
    }

    func test_acknowledgeFlattensAReplyThatIsOnlyAQuestion() {
        let result = DialogueDiffusion.denoise(
            body: "What are you holding onto?",
            policy: .acknowledge,
            userTurn: "goodnight"
        )
        XCTAssertEqual(result.body, "What are you holding onto.")
        XCTAssertEqual(result.applied, ["dialogue.questionOnAcknowledge"])
        XCTAssertEqual(result.infill.map(\.code), ["dialogue.questionOnAcknowledge"])
        let instruction = DialogueDiffusion.infillInstruction(
            for: result.infill[0], policy: .acknowledge
        )
        XCTAssertTrue(instruction.contains("no question"))
    }

    func test_reflectKeepsTheLastQuestion() {
        let result = DialogueDiffusion.denoise(
            body: "Was the lab cold? Did you tell Maya?",
            policy: .reflect,
            userTurn: "Saw a rat in the lab fridge"
        )
        XCTAssertEqual(result.body, "Did you tell Maya?")
        XCTAssertEqual(result.applied, ["dialogue.surplusQuestion"])
        XCTAssertTrue(result.infill.isEmpty)
    }

    func test_reflectWithNoQuestionAsksForOneInfill() {
        let body = "That rat in the fridge."
        let result = DialogueDiffusion.denoise(
            body: body, policy: .reflect, userTurn: "Saw a rat in the lab fridge"
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.applied.isEmpty)
        XCTAssertEqual(result.infill.map(\.code), ["dialogue.missingOpen"])
        XCTAssertTrue(
            DialogueDiffusion.infillInstruction(for: result.infill[0], policy: .reflect)
                .contains("one question")
        )
    }

    func test_listKeepsOneQuestionAndNamesYouShould() {
        let body = "You should take the meeting. Or wait until Friday?"
        let result = DialogueDiffusion.denoise(
            body: body,
            policy: .list,
            userTurn: "What should I do about the work situation"
        )
        XCTAssertEqual(result.body, body)
        XCTAssertTrue(result.applied.isEmpty)
        XCTAssertEqual(result.infill.map(\.code), ["dialogue.youShould"])
        let instruction = DialogueDiffusion.infillInstruction(
            for: result.infill[0], policy: .list
        )
        XCTAssertTrue(instruction.contains("without \"you should\""))
        XCTAssertTrue(instruction.contains("You should take the meeting."))
    }

    func test_youShouldInTheirWordsIsNotNoise() {
        let body = "You should have seen it, you said."
        let result = DialogueDiffusion.denoise(
            body: body,
            policy: .reflect,
            userTurn: "you should have seen it"
        )
        XCTAssertTrue(result.infill.filter { $0.code == "dialogue.youShould" }.isEmpty)
    }

    func test_perceptionAndNarrativeJoinStayInTheBody() {
        let body = "I saw that rat too. You're holding the silence."
        let result = DialogueDiffusion.denoise(
            body: body,
            policy: .reflect,
            userTurn: "Saw a rat in the lab fridge"
        )
        XCTAssertEqual(result.body, body)
        XCTAssertEqual(
            result.infill.map(\.code),
            ["dialogue.missingOpen", "dialogue.perception", "dialogue.narrativeJoin"]
        )
    }

    func test_iHearYouIsNotPerception() {
        let body = "I hear you. I'm here."
        let result = DialogueDiffusion.denoise(
            body: body, policy: .reflect, userTurn: "long day"
        )
        XCTAssertTrue(result.infill.filter { $0.code == "dialogue.perception" }.isEmpty)
        XCTAssertEqual(result.infill.map(\.code), ["dialogue.missingOpen"])
    }

    func test_narrativeJoinAlreadyInTheUserTurnIsTheirs() {
        let body = "You're holding it the way you said."
        let result = DialogueDiffusion.denoise(
            body: body,
            policy: .answer,
            userTurn: "you're holding it together"
        )
        XCTAssertTrue(result.infill.filter { $0.code == "dialogue.narrativeJoin" }.isEmpty)
    }

    func test_bannedOpenerIsNamedAndNotStripped() {
        let body = "You wrote about the lab on Tuesday. It was cold."
        let result = DialogueDiffusion.denoise(
            body: body, policy: .answer, userTurn: "what happened at the lab"
        )
        XCTAssertEqual(result.body, body)
        XCTAssertEqual(result.infill.map(\.code), ["dialogue.bannedOpener"])
    }

    func test_listDropsTheEarlierOfTwoQuestions() {
        let result = DialogueDiffusion.denoise(
            body: "Take the meeting. Or wait until Friday? Or ask Maya?",
            policy: .list,
            userTurn: "Give me a next-step list"
        )
        XCTAssertEqual(result.body, "Take the meeting. Or ask Maya?")
        XCTAssertEqual(result.applied, ["dialogue.surplusQuestion"])
    }
}
