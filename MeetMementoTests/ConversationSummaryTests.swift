import XCTest
@testable import MeetMemento

final class ConversationSummaryTests: XCTestCase {

    func test_keepsARealTitle() {
        let summary = ConversationSummary(
            title: "Afraid to start the side project",
            body: "I keep putting off the side project because I am afraid it will not be good enough."
        ).resolved()
        XCTAssertEqual(summary.title, "Afraid to start the side project")
    }

    func test_dropsChatReflectionAndDerivesFromBody() {
        let summary = ConversationSummary(
            title: "Chat Reflection",
            body: "I realized starting is the hard part. I want to block an hour tomorrow."
        ).resolved()
        XCTAssertEqual(summary.title, "I realized starting is the hard part")
        XCTAssertFalse(summary.title.lowercased().contains("chat"))
    }

    func test_dropsBareChatAndQuotedTitles() {
        XCTAssertEqual(
            ConversationSummary.resolvedTitle("Chat", body: "I want to be kinder to myself this week."),
            "I want to be kinder to myself this week"
        )
        XCTAssertEqual(
            ConversationSummary.resolvedTitle("\"Morning fog\"", body: "unused"),
            "Morning fog"
        )
    }

    func test_emptyBodyFallsBackToJournalEntry() {
        XCTAssertEqual(ConversationSummary.resolvedTitle("", body: "   "), "Journal Entry")
    }
}
