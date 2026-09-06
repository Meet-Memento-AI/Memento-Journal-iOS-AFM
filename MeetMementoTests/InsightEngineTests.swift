import XCTest
@testable import MeetMemento

/// 045 R1 / R5: InsightEngine goldens on the persona corpus. SDK-free.
final class InsightEngineTests: XCTestCase {

    private func isoCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func test_sparseWeeks_areLowConfidence() throws {
        let (entries, _) = try ChatEvalCorpus.personaCorpus()
        let calendar = isoCalendar()
        let december = InsightEngine.weekCadence(
            entries: entries, containing: day(2025, 12, 22, calendar: calendar), calendar: calendar
        )
        let may = InsightEngine.weekCadence(
            entries: entries, containing: day(2026, 5, 4, calendar: calendar), calendar: calendar
        )
        XCTAssertEqual(december.n, 2)
        XCTAssertEqual(may.n, 2)
        XCTAssertTrue(december.isLowConfidence)
        XCTAssertTrue(may.isLowConfidence)
        XCTAssertTrue(InsightFact.lowConfidenceCopy(n: 2).contains("Based on 2 entries"))
    }

    func test_pinnedNow_weekAndMonthCountsMatchSwift() throws {
        let (entries, _) = try ChatEvalCorpus.personaCorpus()
        let calendar = isoCalendar()
        let now = entries.map(\.createdAt).max() ?? Date()
        let week = InsightEngine.weekCadence(entries: entries, containing: now, calendar: calendar)
        let month = InsightEngine.monthCadence(entries: entries, containing: now, calendar: calendar)
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: now, duration: 7 * 86_400)
        let monthInterval = calendar.dateInterval(of: .month, for: now)
            ?? DateInterval(start: now, duration: 30 * 86_400)
        XCTAssertEqual(week.n, entries.filter { weekInterval.contains($0.createdAt) }.count)
        XCTAssertEqual(month.n, entries.filter { monthInterval.contains($0.createdAt) }.count)
        XCTAssertEqual(PatternStats.week(entries: entries, now: now, calendar: calendar).entryCount, week.n)
        XCTAssertEqual(PatternStats.month(entries: entries, now: now, calendar: calendar).entryCount, month.n)
    }

    func test_peopleOrBrotherCount_hasSignal() throws {
        let (entries, _) = try ChatEvalCorpus.personaCorpus()
        let now = entries.map(\.createdAt).max() ?? Date()
        let facts = InsightEngine.facts(entries: entries, now: now)
        let dario = facts.first { $0.kind == .person && $0.label.localizedCaseInsensitiveContains("dario") }
        let brotherHits = entries.filter { InsightEngine.containsSubject($0, "brother") }
        XCTAssertFalse(brotherHits.isEmpty, "corpus must mention brother")
        if let dario {
            XCTAssertGreaterThanOrEqual(dario.n, 1)
        } else {
            XCTAssertGreaterThanOrEqual(brotherHits.count, 1)
        }
    }

    func test_answer_brotherThisYear_matchesSwiftSubjectCount() throws {
        let (entries, _) = try ChatEvalCorpus.personaCorpus()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "UTC")!
        let now = day(2026, 12, 15, calendar: calendar)
        let query = "How many times did I write about my brother this year?"
        XCTAssertEqual(TurnClassifier.classify(query, hasHistory: false), .quantitative)
        let facts = InsightEngine.answer(query: query, entries: entries, now: now, calendar: calendar)
        XCTAssertEqual(facts.count, 1)
        let yearStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let yearEnd = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        let expected = entries.filter {
            $0.createdAt >= yearStart && $0.createdAt < yearEnd
                && InsightEngine.containsSubject($0, "brother")
        }
        XCTAssertEqual(facts[0].n, expected.count)
        XCTAssertEqual(facts[0].kind, .count)
        XCTAssertGreaterThanOrEqual(facts[0].n, 3, "2026 fixtures mention brother at least three times")
    }

    func test_constructedThreeEntryWindow_isLowConfidence() {
        let calendar = isoCalendar()
        let now = day(2026, 8, 23, calendar: calendar)
        let entries = (0..<3).map { offset in
            Entry(
                title: "E\(offset)",
                text: "short note \(offset)",
                createdAt: calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            )
        }
        let week = InsightEngine.weekCadence(entries: entries, containing: now, calendar: calendar)
        XCTAssertEqual(week.n, 3)
        XCTAssertTrue(week.isLowConfidence)
        XCTAssertEqual(InsightFact.lowConfidenceCopy(n: 3), "Based on 3 entries — too few to call a pattern.")
    }

    func test_insightScoring_digitDisagreesAndSuppressedAreReportedNotGated() {
        let window = DateInterval(start: Date(), duration: 86_400)
        let fact = InsightFact(
            kind: .count, label: "brother", value: "3", n: 3,
            window: window, supportingEntryIDs: []
        )
        let disagree = ChatEvalScoring.insightDigitDisagrees(
            body: "You wrote about your brother 9 times.", facts: [fact]
        )
        XCTAssertEqual(disagree.map(\.code), ["insight.digitDisagrees"])
        XCTAssertTrue(ChatEvalScoring.gating(disagree).isEmpty)

        let ok = ChatEvalScoring.insightDigitDisagrees(
            body: "You wrote about your brother 3 times.", facts: [fact]
        )
        XCTAssertTrue(ok.isEmpty)

        let emptyBody = ChatEvalScoring.insightDigitDisagrees(body: "", facts: [fact])
        XCTAssertTrue(emptyBody.isEmpty, "statistic short-circuit has no body to disagree")

        let low = InsightFact(
            kind: .count, label: "sleep", value: "2", n: 2,
            window: window, supportingEntryIDs: []
        )
        let suppressed = ChatEvalScoring.insightContradictsSuppressed(
            body: "Sleep is a clear pattern for you.", facts: [low]
        )
        XCTAssertEqual(suppressed.map(\.code), ["insight.contradictsSuppressed"])
        XCTAssertTrue(ChatEvalScoring.gating(suppressed).isEmpty)
    }

    func test_plainText_includesNAndLowConfidenceCopy() {
        let window = DateInterval(start: Date(), duration: 86_400)
        let fact = InsightFact(
            kind: .count, label: "brother", value: "3", n: 3,
            window: window, supportingEntryIDs: []
        )
        XCTAssertTrue(fact.plainText.contains("3"))
        XCTAssertTrue(fact.plainText.contains("n = 3"))
        XCTAssertTrue(fact.plainText.contains("Based on 3 entries"))

        let content = AIOutputContent(body: "", facts: [fact])
        XCTAssertEqual(content.speakableBody, fact.plainText)
        XCTAssertTrue(content.plainTextForCopy.contains("n = 3"))
        XCTAssertFalse(
            SpeechTextSanitizer.speakableText(
                heading1: nil, heading2: nil, body: content.speakableBody
            ).isEmpty
        )
    }
}
