import XCTest
@testable import MeetMemento

final class LoadingStatusTests: XCTestCase {

    func test_phrase_mapsEveryTurnType() {
        XCTAssertEqual(LoadingStatus.phrase(for: .journalQuery), "Reviewing your past entries…")
        XCTAssertEqual(LoadingStatus.phrase(for: .reflectiveQuestion), "Reviewing your past entries…")
        XCTAssertEqual(LoadingStatus.phrase(for: .share), "Reviewing your past entries…")

        XCTAssertEqual(LoadingStatus.phrase(for: .social), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .acknowledgement), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .meta), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .offdomain), LoadingStatus.fallback)
        XCTAssertEqual(LoadingStatus.phrase(for: .followup), LoadingStatus.fallback)
    }

    func test_followUpPhrase_onlyRetrievalTurns() {
        XCTAssertEqual(LoadingStatus.followUpPhrase(for: .share), "Finding what fits…")
        XCTAssertEqual(LoadingStatus.followUpPhrase(for: .journalQuery), "Finding what fits…")
        XCTAssertEqual(LoadingStatus.followUpPhrase(for: .reflectiveQuestion), "Finding what fits…")

        XCTAssertNil(LoadingStatus.followUpPhrase(for: .social))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .acknowledgement))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .meta))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .offdomain))
        XCTAssertNil(LoadingStatus.followUpPhrase(for: .followup))
    }

    func test_sessionLoad_andFallback() {
        XCTAssertEqual(LoadingStatus.sessionLoad, "Opening this conversation…")
        XCTAssertEqual(LoadingStatus.fallback, "Memento is thinking…")
    }
}
