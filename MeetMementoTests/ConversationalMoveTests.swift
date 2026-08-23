import XCTest
@testable import MeetMemento

/// Spec 039 R9: short warm cues, not scripts. Light path is one Move + message.
final class ConversationalMoveTests: XCTestCase {

    func test_hello_isGreetAndAsk() {
        let move = ConversationalMove.resolve(
            turn: .social, message: "hello", history: [], hasEvidence: false
        )
        XCTAssertEqual(move, .greetAndAsk)
        XCTAssertFalse(move.skipsQuestion)
        XCTAssertTrue(move.invitesName)
        XCTAssertFalse(move.avoidsName)
        XCTAssertTrue(move.cueLine.contains("Warm hello"))
        XCTAssertTrue(move.cueLine.contains("first or last name is welcome"))
        XCTAssertTrue(move.cueLine.hasPrefix("[Move: "))
    }

    func test_howAreYou_isNotGreetAndAsk() {
        for sample in ["how are you", "Hello, how are you", "what's up", "how's it going"] {
            let move = ConversationalMove.resolve(
                turn: .social, message: sample, history: [], hasEvidence: false
            )
            XCTAssertEqual(move, .answerHowAreYou, sample)
            XCTAssertTrue(move.cueLine.contains("Do not echo"), sample)
            XCTAssertTrue(move.cueLine.contains("name is optional"), sample)
            XCTAssertFalse(move.invitesName, sample)
            XCTAssertFalse(move.avoidsName, sample)
        }
    }

    func test_thanks_and_farewell() {
        XCTAssertEqual(
            ConversationalMove.resolve(turn: .social, message: "thanks", history: [], hasEvidence: false),
            .thanks
        )
        let bye = ConversationalMove.resolve(
            turn: .social, message: "goodbye", history: [], hasEvidence: false
        )
        XCTAssertEqual(bye, .farewell)
        XCTAssertTrue(bye.skipsQuestion)
        XCTAssertTrue(bye.cueLine.contains("No interrogation"))
        XCTAssertTrue(bye.cueLine.contains("first or last name is welcome"))
        XCTAssertTrue(
            ConversationalMove.thanks.cueLine.contains("first or last name is welcome")
        )
        XCTAssertEqual(
            ConversationalMove.resolve(turn: .social, message: "good night", history: [], hasEvidence: false),
            .farewell
        )
    }

    func test_continuer() {
        let move = ConversationalMove.resolve(
            turn: .acknowledgement, message: "yeah", history: [], hasEvidence: false
        )
        XCTAssertEqual(move, .continuer)
        XCTAssertTrue(move.avoidsName)
        XCTAssertFalse(move.invitesName)
        XCTAssertTrue(move.cueLine.contains("new question"))
        XCTAssertTrue(move.cueLine.contains("Do not use their name"))
    }

    func test_share_withoutEvidence_reflects() {
        XCTAssertEqual(
            ConversationalMove.resolve(turn: .share, message: "work was a lot", history: [], hasEvidence: false),
            .reflectAndAsk
        )
    }

    func test_journalWithEvidence_isPatternThenAsk() {
        XCTAssertEqual(
            ConversationalMove.resolve(turn: .journalQuery, message: "what did I write about work?", history: [], hasEvidence: true),
            .patternThenAsk
        )
        XCTAssertTrue(ConversationalMove.patternThenAsk.avoidsName)
        XCTAssertTrue(ConversationalMove.patternThenAsk.cueLine.contains("Do not use their name"))
        XCTAssertEqual(
            ConversationalMove.resolve(turn: .journalQuery, message: "what did I write about work?", history: [], hasEvidence: false),
            .emptyThenAsk
        )
    }

    func test_metaAndOffdomain() {
        XCTAssertEqual(
            ConversationalMove.resolve(turn: .meta, message: "what can you do", history: [], hasEvidence: false),
            .answerThenAsk
        )
        XCTAssertEqual(
            ConversationalMove.resolve(turn: .offdomain, message: "what is the capital of France", history: [], hasEvidence: false),
            .redirectThenAsk
        )
    }

    func test_antiRepeat_extractsLastAssistantQuestion() {
        let history = [
            ChatTurn(role: .user, text: "hello"),
            ChatTurn(role: .assistant, text: "Hey. How has the week been treating you?")
        ]
        XCTAssertEqual(
            ConversationalMove.lastAssistantQuestion(in: history),
            "How has the week been treating you?"
        )
        let line = ConversationalMove.antiRepeatLine(from: history)
        XCTAssertEqual(line, "[Don't ask that again: \"How has the week been treating you?\"]")
    }

    func test_antiRepeat_nilWhenNoQuestion() {
        let history = [ChatTurn(role: .assistant, text: "Take care.")]
        XCTAssertNil(ConversationalMove.lastAssistantQuestion(in: history))
        XCTAssertNil(ConversationalMove.antiRepeatLine(from: history))
    }

    func test_everyMove_hasACue() {
        for move in ConversationalMove.allCases {
            XCTAssertTrue(move.cueLine.hasPrefix("[Move: "), "\(move)")
            XCTAssertTrue(move.cueLine.hasSuffix("]"), "\(move)")
        }
    }
}
