import XCTest
@testable import withMemento

final class ResponsePolicyTests: XCTestCase {

    func test_adviceOpener_isList() {
        let question = "What should I do about the work situation"
        let turn = TurnClassifier.classify(question, hasHistory: false)
        let shape = QuestionShapeResolver.shape(of: question, turn: turn)
        XCTAssertEqual(shape, .advice)
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .list)
        XCTAssertFalse(ResponsePolicyResolver.openRequired(policy: .list, bodyIsEmpty: false))
        XCTAssertTrue(PromptRegistry.policySuffix(.list).contains("Never \"you should\""))
    }

    func test_goodbye_isAcknowledge() {
        let question = "goodnight"
        let turn = TurnClassifier.classify(question, hasHistory: false)
        XCTAssertEqual(turn, .social)
        let shape = QuestionShapeResolver.shape(of: question, turn: turn)
        XCTAssertEqual(shape, .goodbye)
        XCTAssertEqual(ResponsePolicyResolver.policy(shape: shape), .acknowledge)
        let suffix = PromptRegistry.policySuffix(.acknowledge)
        XCTAssertTrue(suffix.contains("No question"))
        XCTAssertFalse(suffix.lowercased().contains("holding"))
    }

    func test_lastTuesday_isThePreviousTuesday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        // Wednesday 16 September 2026.
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16))!
        let window = QueryDateWindowParser.parse("what happened last Tuesday", now: now, calendar: calendar)
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!
        let wednesday = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16))!
        XCTAssertEqual(window?.start, tuesday)
        XCTAssertEqual(window?.end, wednesday)
    }

    func test_beforePottery_doesNotRankThePotteryEntryFirst() throws {
        let (entries, ids) = try ChatEvalCorpus.coldStartCorpus()
        let question = "What was bothering me before the pottery class"
        XCTAssertEqual(QueryDateWindowParser.beforeAnchor(question), "pottery class")
        let result = EntryRetriever.retrieve(
            RetrievalQuery(currentMessage: question),
            entries: entries
        )
        let ranked = result.entries.compactMap { ids[$0.id] }
        XCTAssertFalse(ranked.contains("cs-01"), "ranked \(ranked)")
        if let first = ranked.first {
            XCTAssertNotEqual(first, "cs-01")
        }
    }
}
