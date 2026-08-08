import XCTest
@testable import MeetMemento

final class RetrievalPolicyTests: XCTestCase {

    // MARK: - Mode matrix

    func test_modeMatrix() {
        XCTAssertEqual(RetrievalPolicy.mode(for: .social), .none)
        XCTAssertEqual(RetrievalPolicy.mode(for: .acknowledgement), .none)
        XCTAssertEqual(RetrievalPolicy.mode(for: .meta), .none)
        XCTAssertEqual(RetrievalPolicy.mode(for: .offdomain), .none)
        XCTAssertEqual(RetrievalPolicy.mode(for: .followup), .reusePrevious)
        XCTAssertEqual(RetrievalPolicy.mode(for: .share), .currentOnly(highBar: true))
        XCTAssertEqual(RetrievalPolicy.mode(for: .journalQuery), .currentWeighted)
        XCTAssertEqual(RetrievalPolicy.mode(for: .reflectiveQuestion), .currentWeighted)
    }

    // MARK: - Followup anchor

    private func user(_ text: String) -> ChatTurn { ChatTurn(role: .user, text: text) }
    private func memento(_ text: String) -> ChatTurn { ChatTurn(role: .assistant, text: text) }

    func test_followupAnchor_findsLastSubstantiveUserTurn() {
        let history = [
            user("what did I write about work stress?"),
            memento("In your entries this month, deadlines come up a lot…"),
            user("haha yeah"),
            memento("It sounds familiar to you."),
        ]
        XCTAssertEqual(RetrievalPolicy.followupAnchor(history: history), "what did I write about work stress?")
    }

    func test_followupAnchor_skipsFollowupsAndSocial(){
        let history = [
            user("have I mentioned my sister lately?"),
            memento("A few times, most recently on Tuesday…"),
            user("tell me more"),
            memento("You wrote that…"),
            user("thanks"),
        ]
        XCTAssertEqual(RetrievalPolicy.followupAnchor(history: history), "have I mentioned my sister lately?")
    }

    func test_followupAnchor_nilOnEmptyOrAllTrivial() {
        XCTAssertNil(RetrievalPolicy.followupAnchor(history: []))
        XCTAssertNil(RetrievalPolicy.followupAnchor(history: [user("hey"), memento("Hi!"), user("thanks")]))
    }

    func test_followupAnchor_capsWalkback() {
        let history = [
            user("what did I write about running?"),   // substantive but beyond cap
            user("hmm"), user("ok"), user("thanks"), user("haha"),
        ]
        XCTAssertNil(RetrievalPolicy.followupAnchor(history: history, maxWalkback: 4))
    }

    // MARK: - Stance resolution

    private func grounded() -> RetrievalResult {
        RetrievalResult(entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "x")], contextBlock: "[Journal context]", isAmbient: false)
    }

    private func ambient() -> RetrievalResult {
        RetrievalResult(entries: [RetrievedEntry(ref: 1, id: UUID(), date: Date(), text: "x")], contextBlock: "[Recent…]", isAmbient: true)
    }

    func test_stance_noRetrievalTypes() {
        XCTAssertEqual(RetrievalPolicy.stance(turn: .social, retrieval: .empty), .casual)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .acknowledgement, retrieval: .empty), .casual)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .meta, retrieval: .empty), .aboutApp)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .offdomain, retrieval: .empty), .outsideScope)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .followup, retrieval: grounded()), .followupThread)
    }

    func test_stance_sharePromotesOnlyOnRealMatch() {
        XCTAssertEqual(RetrievalPolicy.stance(turn: .share, retrieval: grounded()), .journalGrounded)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .share, retrieval: ambient()), .sharing)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .share, retrieval: .empty), .sharing)
    }

    func test_stance_journalQueryHonestOnNoMatch() {
        XCTAssertEqual(RetrievalPolicy.stance(turn: .journalQuery, retrieval: grounded()), .journalGrounded)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .journalQuery, retrieval: ambient()), .noMatch)
        XCTAssertEqual(RetrievalPolicy.stance(turn: .journalQuery, retrieval: .empty), .noMatch)
    }

    func test_stance_reflectiveDegradesToSharingNotRefusal() {
        XCTAssertEqual(RetrievalPolicy.stance(turn: .reflectiveQuestion, retrieval: ambient()), .sharing)
    }

    func test_groundedFlag() {
        XCTAssertTrue(TurnStance.journalGrounded.isGrounded)
        XCTAssertTrue(TurnStance.followupThread.isGrounded)
        for stance in TurnStance.allCases where !(stance == .journalGrounded || stance == .followupThread) {
            XCTAssertFalse(stance.isGrounded, "\(stance)")
        }
    }
}
