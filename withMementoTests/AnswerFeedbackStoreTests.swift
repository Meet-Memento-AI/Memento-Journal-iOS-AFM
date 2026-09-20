import XCTest
@testable import MeetMemento

final class AnswerFeedbackStoreTests: XCTestCase {

    private func makeStore() -> (AnswerFeedbackStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnswerFeedback-\(UUID().uuidString)", isDirectory: true)
        return (AnswerFeedbackStore(directory: dir), dir)
    }

    func test_upsert_roundTripsAcrossInstances() {
        let (store, dir) = makeStore()
        let messageID = UUID()
        _ = store.upsert(AnswerFeedback(
            messageID: messageID,
            rating: .positive,
            source: .thumbsUp,
            userPrompt: "How was Tuesday?",
            assistantReply: "You wrote about eggs.",
            promptVersion: "ask@14"
        ))
        store.flush()

        let reloaded = AnswerFeedbackStore(directory: dir)
        let row = reloaded.feedback(for: messageID)
        XCTAssertEqual(row?.rating, .positive)
        XCTAssertEqual(row?.userPrompt, "How was Tuesday?")
        XCTAssertEqual(row?.assistantReply, "You wrote about eggs.")
        XCTAssertEqual(row?.promptVersion, "ask@14")
    }

    func test_upsert_sameMessageID_updatesInPlace() {
        let (store, _) = makeStore()
        let messageID = UUID()
        _ = store.upsert(AnswerFeedback(
            messageID: messageID,
            rating: .positive,
            source: .thumbsUp,
            assistantReply: "first"
        ))
        _ = store.upsert(AnswerFeedback(
            messageID: messageID,
            rating: .negative,
            flaggedForReview: true,
            category: .wrongRecall,
            source: .report,
            assistantReply: "first"
        ))
        let row = store.feedback(for: messageID)
        XCTAssertEqual(row?.rating, .negative)
        XCTAssertTrue(row?.flaggedForReview ?? false)
        XCTAssertEqual(row?.category, .wrongRecall)
        XCTAssertEqual(store.all().count, 1)
    }

    func test_clear_removesRows() {
        let (store, dir) = makeStore()
        let messageID = UUID()
        _ = store.upsert(AnswerFeedback(messageID: messageID, rating: .positive, source: .thumbsUp))
        store.clear()
        XCTAssertNil(store.feedback(for: messageID))
        store.flush()
        let reloaded = AnswerFeedbackStore(directory: dir)
        XCTAssertNil(reloaded.feedback(for: messageID))
    }

    func test_exportJSONData_emptyIsNil() throws {
        let (store, _) = makeStore()
        XCTAssertNil(try store.exportJSONData())
    }

    func test_feedbackMatching_findsByAssistantReply() {
        let (store, _) = makeStore()
        let originalID = UUID()
        _ = store.upsert(AnswerFeedback(
            messageID: originalID,
            rating: .negative,
            source: .thumbsDown,
            assistantReply: "You wrote about eggs."
        ))
        let match = store.feedbackMatching(assistantReply: "You wrote about eggs.")
        XCTAssertEqual(match?.messageID, originalID)
        XCTAssertNil(store.feedbackMatching(assistantReply: "something else"))
    }
}
