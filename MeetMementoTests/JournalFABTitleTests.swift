import XCTest
@testable import MeetMemento

final class JournalFABTitleTests: XCTestCase {
    func test_beforeLoad_neverUsesEmptyCopy() {
        XCTAssertEqual(
            JournalFABTitle.resolved(hasInitiallyLoaded: false, isEmpty: true),
            JournalFABTitle.hasEntries
        )
        XCTAssertEqual(
            JournalFABTitle.resolved(hasInitiallyLoaded: false, isEmpty: false),
            JournalFABTitle.hasEntries
        )
    }

    func test_afterLoad_emptyJournal_usesFirstEntryCopy() {
        XCTAssertEqual(
            JournalFABTitle.resolved(hasInitiallyLoaded: true, isEmpty: true),
            JournalFABTitle.emptyJournal
        )
    }

    func test_afterLoad_withEntries_usesNewEntry() {
        XCTAssertEqual(
            JournalFABTitle.resolved(hasInitiallyLoaded: true, isEmpty: false),
            JournalFABTitle.hasEntries
        )
    }
}
