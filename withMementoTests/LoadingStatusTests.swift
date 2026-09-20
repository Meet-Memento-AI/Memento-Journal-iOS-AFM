import XCTest
@testable import MeetMemento

final class LoadingStatusTests: XCTestCase {

    private func user(_ text: String) -> ChatTurn { ChatTurn(role: .user, text: text) }
    private func memento(_ text: String) -> ChatTurn { ChatTurn(role: .assistant, text: text) }

    func test_phrase_mapsEveryTurnType() {
        XCTAssertEqual(LoadingStatus.phrase(for: .journalQuery), "Reviewing your past entries…")
        XCTAssertEqual(LoadingStatus.phrase(for: .reflectiveQuestion), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .share), LoadingStatus.fallback)

        XCTAssertEqual(LoadingStatus.phrase(for: .social), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .acknowledgement), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .meta), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .offdomain), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .followup), LoadingStatus.fallback)
    }

    func test_share_isNotReviewingPastEntries() {
        XCTAssertNotEqual(LoadingStatus.phrase(for: .share), "Reviewing your past entries…")
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .share))
    }

    func test_followUpPhrase_onlyRetrievalTurns() {
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .share))
        XCTAssertEqual(LoadingStatus.followUpPhrase(for: .journalQuery), "Finding what fits…")
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .reflectiveQuestion))

        XCTAssertNil(LoadingStatus.followUpPhrase(for: .social))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .acknowledgement))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .meta))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .offdomain))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .followup))
    }

    func test_followup_afterJournalAsk_usesRetrievalCopy() {
        let history = [
            user("what did I write about work stress?"),
            memento("Deadlines come up…"),
        ]
        XCTAssertEqual(
            LoadingStatus.phrase(for: .followup, history: history),
            "Reviewing your past entries…"
        )
        XCTAssertEqual(
            LoadingStatus.followUpPhrase(for: .followup, history: history),
            "Finding what fits…"
        )
    }

    func test_followup_afterShare_usesThinkingFallback() {
        let history = [
            user("today was exhausting, meetings all day"),
            memento("That sounds like a long one."),
        ]
        XCTAssertEqual(
            LoadingStatus.phrase(for: .followup, history: history),
            LoadingStatus.fallback
        )
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .followup, history: history))
    }

    func test_sessionLoad_andFallback() {
        XCTAssertEqual(LoadingStatus.sessionLoad, "Opening this conversation…")
        XCTAssertEqual(LoadingStatus.fallback, "Memento is thinking…")
    }
}
