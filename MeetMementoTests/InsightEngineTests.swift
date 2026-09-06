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

    func test_streakAndGap_nIsEntrySampleSizeNotDayCount() {
        let calendar = isoCalendar()
        let now = day(2026, 8, 23, calendar: calendar)
        // Three-day streak, one entry per day — n is 3 entries, not a day label.
        let streakEntries = (0..<3).map { offset in
            Entry(
                title: "S\(offset)",
                text: "streak note \(offset)",
                createdAt: calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            )
        }
        let streak = InsightEngine.streakFact(
            sorted: streakEntries.sorted { $0.createdAt < $1.createdAt },
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(streak?.value, "3 days")
        XCTAssertEqual(streak?.n, 3)
        XCTAssertEqual(streak?.supportingEntryIDs.count, 3)
        XCTAssertEqual(streak?.isLowConfidence, true)

        let confidentStreakEntries = (0..<4).map { offset in
            Entry(
                title: "C\(offset)",
                text: "confident streak \(offset)",
                createdAt: calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            )
        }
        let confident = InsightEngine.streakFact(
            sorted: confidentStreakEntries.sorted { $0.createdAt < $1.createdAt },
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(confident?.n, 4)
        XCTAssertEqual(confident?.isLowConfidence, false)

        // A 30-day silence is two bounding entries. n=30 would have claimed
        // a confident pattern from two points; n=2 greys it.
        let early = Entry(
            title: "Before",
            text: "first",
            createdAt: calendar.date(byAdding: .day, value: -30, to: now) ?? now
        )
        let late = Entry(title: "After", text: "second", createdAt: now)
        let gap = InsightEngine.longestGapFact(
            sorted: [early, late],
            calendar: calendar
        )
        XCTAssertEqual(gap?.value, "30 days")
        XCTAssertEqual(gap?.n, 2)
        XCTAssertEqual(gap?.supportingEntryIDs.count, 2)
        XCTAssertEqual(gap?.isLowConfidence, true)
        XCTAssertEqual(
            InsightFact.lowConfidenceCopy(n: gap?.n ?? 0),
            "Based on 2 entries — too few to call a pattern."
        )
    }

    func test_personFact_countsUniqueEntriesNotMentions() {
        let calendar = isoCalendar()
        let now = day(2026, 8, 23, calendar: calendar)
        let one = Entry(
            title: "Call",
            text: "Dario called, then Dario texted later.",
            createdAt: now
        )
        let two = Entry(
            title: "Dinner",
            text: "Dinner with Dario.",
            createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now
        )
        XCTAssertEqual(InsightEngine.uniquedEntries([one, one, two]).map(\.id), [one.id, two.id])
        let facts = InsightEngine.namedEntityFacts(
            entries: [one, two], now: now, calendar: calendar
        )
        let dario = facts.first {
            $0.kind == .person && $0.label.localizedCaseInsensitiveContains("dario")
        }
        if let dario {
            XCTAssertEqual(dario.n, 2, "two mentions in one entry must not inflate n")
            XCTAssertEqual(Set(dario.supportingEntryIDs).count, 2)
            XCTAssertEqual(dario.n, dario.supportingEntryIDs.count)
        }
    }

    func test_facts_nMatchesUniqueSupportingEntryIDs() throws {
        let (entries, _) = try ChatEvalCorpus.personaCorpus()
        let now = entries.map(\.createdAt).max() ?? Date()
        let facts = InsightEngine.facts(entries: entries, now: now)
        XCTAssertFalse(facts.isEmpty)
        for fact in facts {
            XCTAssertEqual(
                fact.n,
                Set(fact.supportingEntryIDs).count,
                "\(fact.kind.rawValue) \(fact.label): n is unique entries"
            )
        }
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

    func test_facts_withNowBeforeCorpus_doesNotTrap() throws {
        let (entries, _) = try ChatEvalCorpus.personaCorpus()
        let calendar = isoCalendar()
        let now = day(2025, 1, 1, calendar: calendar)
        let facts = InsightEngine.facts(entries: entries, now: now, calendar: calendar)
        XCTAssertFalse(facts.isEmpty)
        XCTAssertTrue(facts.allSatisfy { $0.window.duration >= 0 })
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

    /// 045 R5: the live Ask path must return Swift `n` without constructing
    /// a `LanguageModelSession`. Fails in CI if statistic still touches
    /// `SystemLanguageModel` / availability.
    func test_ask_statistic_returnsSwiftFactsWithoutTheModel() async throws {
        let (entries, _) = try ChatEvalCorpus.personaCorpus()
        let query = "How many times did I write about my brother this year?"
        XCTAssertEqual(TurnClassifier.classify(query, hasHistory: false), .quantitative)

        let result = try await FoundationModelsIntelligenceService().ask(
            query, history: [], entries: entries, images: []
        )
        let expected = InsightEngine.answer(query: query, entries: entries)

        XCTAssertEqual(result.promptVersion, "insight-fact@1")
        XCTAssertEqual(result.modelIdentifier, "swift")
        XCTAssertTrue(result.body.isEmpty, "statistic body must not invent a digit")
        XCTAssertEqual(result.facts.count, 1)
        XCTAssertEqual(result.facts.first?.n, expected.first?.n)
        XCTAssertEqual(result.facts.first?.kind, .count)
        XCTAssertTrue(
            ChatEvalScoring.insightDigitDisagrees(body: result.body, facts: result.facts).isEmpty
        )
    }
}
