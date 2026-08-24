import XCTest
@testable import MeetMemento

/// The date grammar behind the temporal half of the gold set. Pure — no model,
/// no simulator, no corpus.
final class QueryDateWindowTests: XCTestCase {

    /// Every case is resolved against a fixed "now" so the expectations are
    /// stable: 23 August 2026, the date the failures were measured.
    private let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 8; c.day = 23
        return Calendar.current.date(from: c)!
    }()

    private func window(_ q: String) -> QueryDateWindow? {
        QueryDateWindowParser.parse(q, now: now)
    }

    private func assertWindow(_ q: String, year: Int, month: Int, months: Int = 1,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard let w = window(q) else { return XCTFail("no window for \"\(q)\"", file: file, line: line) }
        let cal = Calendar.current
        let expectedStart = cal.date(from: DateComponents(year: year, month: month, day: 1))!
        let expectedEnd = cal.date(byAdding: .month, value: months, to: expectedStart)!
        XCTAssertEqual(w.start, expectedStart, "\(q) start", file: file, line: line)
        XCTAssertEqual(w.end, expectedEnd, "\(q) end", file: file, line: line)
    }

    // MARK: - Months

    /// A bare month resolves to its most recent occurrence at or before now —
    /// in August 2026, "December" is December 2025 and "March" is March 2026.
    func test_monthResolvesToMostRecentOccurrence() {
        assertWindow("What did I hear about Nonna's health in December?", year: 2025, month: 12)
        assertWindow("What happened with my knee in March?", year: 2026, month: 3)
        assertWindow("How was coffee with my brother in April?", year: 2026, month: 4)
        assertWindow("Tell me about the fight with Dario in July.", year: 2026, month: 7)
    }

    /// "last December" in August is four months back, not sixteen. Only when
    /// `last` names the month we are *in* does it mean a year ago.
    func test_lastMonth() {
        assertWindow("What was I working on last December?", year: 2025, month: 12)
        assertWindow("What did I write last August?", year: 2025, month: 8)
    }

    func test_monthWithExplicitYear() {
        assertWindow("What did I write in December 2025?", year: 2025, month: 12)
    }

    /// `may` is a modal verb far more often than it is a month, so a month only
    /// counts when a preposition or determiner introduces it.
    func test_bareMonthWordIsNotADate() {
        XCTAssertNil(window("What may I have missed?"))
        XCTAssertNil(window("March straight past the hard part"))
        assertWindow("What did I write in May?", year: 2026, month: 5)
    }

    // MARK: - Seasons

    func test_seasons() {
        // Winter is anchored on its December, so the winter before this August
        // is Dec 2025 – Feb 2026.
        assertWindow("When did I go skiing last winter?", year: 2025, month: 12, months: 3)
        assertWindow("How often did I write about running this spring?", year: 2026, month: 3, months: 3)
        assertWindow("What did I do last summer?", year: 2025, month: 6, months: 3)
    }

    // MARK: - Years

    func test_absoluteYear() {
        guard let w = window("What did I write about my brother in 2025?") else {
            return XCTFail("no window")
        }
        let cal = Calendar.current
        XCTAssertEqual(w.start, cal.date(from: DateComponents(year: 2025, month: 1, day: 1)))
        XCTAssertEqual(w.end, cal.date(from: DateComponents(year: 2026, month: 1, day: 1)))
    }

    func test_thisYearIsACalendarYear() {
        guard let w = window("What has grief looked like for me this year?") else {
            return XCTFail("no window")
        }
        XCTAssertEqual(w.start, Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)))
    }

    /// "the last year" is a rolling twelve months, not calendar 2025 — the
    /// rolling grammar has to win over the calendar one.
    func test_theLastYearIsRolling() {
        guard let w = window("What were my hardest weeks in the last year?") else {
            return XCTFail("no window")
        }
        XCTAssertEqual(w.end.timeIntervalSince(now), 1, accuracy: 2)
        XCTAssertTrue(w.contains(now.addingTimeInterval(-200 * 86_400)))
        XCTAssertFalse(w.contains(now.addingTimeInterval(-400 * 86_400)))
    }

    // MARK: - Must stay off

    /// A false window hides the entries the question was really about, so the
    /// grammar has to decline anything that is not clearly a date.
    func test_ordinaryQuestionsCarryNoWindow() {
        for q in ["When did I first say I was burnt out?",
                  "What have I been writing about lately?",
                  "How have I changed since the start of the year?",
                  "Who is Maya?",
                  "What did I sell at the street market?",
                  "I had a rough day at work today"] {
            XCTAssertNil(window(q), q)
        }
    }
}
