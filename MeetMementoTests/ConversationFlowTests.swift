import XCTest
@testable import MeetMemento

/// Scripted conversations through the deterministic half of the pipeline:
/// classify → policy → (retrieval where deterministic) → stance. This is the
/// executable spec for "casual turns stay conversational, journal asks get
/// grounded, follow-ups continue the thread".
final class ConversationFlowTests: XCTestCase {

    private func user(_ text: String) -> ChatTurn { ChatTurn(role: .user, text: text) }
    private func memento(_ text: String) -> ChatTurn { ChatTurn(role: .assistant, text: text) }

    private func entry(_ title: String, _ text: String) -> Entry {
        Entry(id: UUID(), title: title, text: text, createdAt: Date(), updatedAt: Date(), syncStatus: .synced)
    }

    /// "hey" at conversation start → no retrieval, casual stance, no journal
    /// context regardless of what's in the corpus.
    func test_greeting_staysCasual() {
        let turn = TurnClassifier.classify("hey", hasHistory: false)
        XCTAssertEqual(turn, .social)
        XCTAssertEqual(RetrievalPolicy.mode(for: turn), .none)
        XCTAssertEqual(RetrievalPolicy.stance(turn: turn, retrieval: .empty), .casual)
    }

    /// The regression that motivated the redesign: after a grounded exchange,
    /// "haha yeah" must NOT inherit the previous topic and re-ground.
    func test_acknowledgementAfterGroundedTurn_doesNotInheritTopic() {
        let turn = TurnClassifier.classify("haha yeah", hasHistory: true)
        XCTAssertEqual(turn, .acknowledgement)
        XCTAssertEqual(RetrievalPolicy.mode(for: turn), .none)
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: .empty)
        XCTAssertEqual(stance, .casual)
        XCTAssertFalse(stance.isGrounded, "no citation fallback on casual turns")
    }

    /// "tell me more" anchors retrieval to the earlier substantive ask.
    func test_followup_anchorsToEarlierAsk() {
        let history = [
            user("what did I write about work stress?"),
            memento("Deadlines come up in three entries this month…"),
            user("haha yeah"),
            memento("It seems to be a theme."),
        ]
        let turn = TurnClassifier.classify("tell me more", hasHistory: true)
        XCTAssertEqual(turn, .followup)
        XCTAssertEqual(RetrievalPolicy.mode(for: turn), .reusePrevious)
        XCTAssertEqual(RetrievalPolicy.followupAnchor(history: history), "what did I write about work stress?")
        // Follow-ups keep the thread's grounding privileges.
        XCTAssertTrue(TurnStance.followupThread.isGrounded)
    }

    /// An explicit journal ask that matches an entry ends journalGrounded.
    func test_journalAsk_getsGrounded() {
        let entries = [
            entry("marathon training", "long marathon run this morning, legs sore"),
            entry("random one", "flumox vendrik parlune quostam"),
            entry("random two", "grebbin marzipol wendle forp"),
            entry("random three", "sundry blathe corvin plim"),
            entry("random four", "yulep standrik moven glarp"),
            entry("random five", "quibble ronto passim delve"),
        ]
        let turn = TurnClassifier.classify("what did I write about marathon training?", hasHistory: false)
        XCTAssertEqual(turn, .journalQuery)
        let retrieval = EntryRetriever.retrieve(RetrievalQuery(currentMessage: "what did I write about marathon training?"), entries: entries)
        XCTAssertFalse(retrieval.isAmbient)
        XCTAssertEqual(RetrievalPolicy.stance(turn: turn, retrieval: retrieval), .journalGrounded)
    }

    /// An explicit journal ask about an uncovered topic gets the honest
    /// no-match stance, not a fabricated grounding.
    func test_journalAsk_uncoveredTopic_isNoMatch() {
        let turn = TurnClassifier.classify("what have I written about sailing?", hasHistory: false)
        XCTAssertEqual(turn, .journalQuery)
        let ambient = RetrievalResult(
            entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "x")],
            contextBlock: "[Recent…]", isAmbient: true
        )
        XCTAssertEqual(RetrievalPolicy.stance(turn: turn, retrieval: ambient), .noMatch)
    }

    /// Venting stays conversational — never promoted to journalGrounded.
    func test_share_staysConversationalByDefault() {
        let turn = TurnClassifier.classify("today was exhausting, meetings all day", hasHistory: true)
        XCTAssertEqual(turn, .share)
        XCTAssertEqual(RetrievalPolicy.mode(for: turn), .currentOnly(highBar: true))
        let stance = RetrievalPolicy.stance(turn: turn, retrieval: .empty)
        XCTAssertEqual(stance, .sharing)
        XCTAssertFalse(stance.isGrounded)
    }

    /// Even a strong retrieval hit must not turn a share into an entry report.
    func test_share_neverPromotesToJournalGrounded() {
        let turn = TurnClassifier.classify("today was exhausting, meetings all day", hasHistory: true)
        let strong = RetrievalResult(
            entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "meetings drained me")],
            contextBlock: "[ref 1]",
            isAmbient: false
        )
        XCTAssertEqual(RetrievalPolicy.stance(turn: turn, retrieval: strong), .sharing)
    }

    /// Reflective musings stay conversational (grounded reserved for journal asks).
    func test_reflectiveQuestion_staysSharing() {
        let turn = TurnClassifier.classify("why do I keep doing this?", hasHistory: true)
        XCTAssertEqual(turn, .reflectiveQuestion)
        let strong = RetrievalResult(
            entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "I keep repeating the same pattern")],
            contextBlock: "[ref 1]",
            isAmbient: false
        )
        XCTAssertEqual(RetrievalPolicy.stance(turn: turn, retrieval: strong), .sharing)
    }

    /// World-fact question → out-of-scope stance, no journal references.
    func test_offdomain_redirects() {
        let turn = TurnClassifier.classify("who won the game last night?", hasHistory: true)
        XCTAssertEqual(turn, .offdomain)
        XCTAssertEqual(RetrievalPolicy.mode(for: turn), .none)
        XCTAssertEqual(RetrievalPolicy.stance(turn: turn, retrieval: .empty), .outsideScope)
    }
}
