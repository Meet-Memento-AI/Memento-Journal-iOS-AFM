//
//  QueryDateWindow.swift
//  MeetMemento
//
//  The date a question names, resolved to a range over the journal.
//
//  `EntryRetriever` ranks on semantics, keyword overlap and recency — none of
//  which can see an entry's `createdAt`. A question that names a month, season
//  or year therefore had no way to reach the entries written then, because the
//  date is metadata and almost never appears in the text. Measured on the
//  262-entry persona corpus (2026-08-23):
//
//    "What did I hear about Nonna's health in December?"  → cited Feb + Apr 2026
//    "What was I working on last December?"               → cited Jul 2026
//    "Tell me about the fight with Dario in July."        → cited nothing
//    "What did I write about my brother in 2025?"         → cited a Mar 2026 entry
//
//  The last one is the worst shape: the corpus has no 2025 entry about the
//  brother at all, so the honest answer is "nothing" — and the reply instead
//  cited March 2026 while claiming it was the answer.
//
//  No `import FoundationModels` — pure Foundation, so the grammar is testable
//  without a model or a simulator.
//

import Foundation

/// A date range a question named, with the span of text that named it.
struct QueryDateWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    /// The matched words ("in december", "last winter", "2025"), lowercased.
    /// `EntryRetriever` subtracts these from the keyword terms so the month
    /// name cannot also be scored as content.
    let matchedText: String

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

enum QueryDateWindowParser {

    /// Resolve the date range a question names, if it names one.
    ///
    /// Deliberately conservative — a false window is worse than none, because
    /// it hides entries the question was really about. Every month/season match
    /// must carry a preposition or a `last`/`this` determiner, which is what
    /// keeps "May" the month apart from "may" the modal, and stops an ordinary
    /// sentence from being read as a date.
    static func parse(_ query: String, now: Date = Date(),
                      calendar: Calendar = .current) -> QueryDateWindow? {
        let lower = query.lowercased()
        var cal = calendar
        cal.timeZone = calendar.timeZone

        // Order matters: the most specific grammar first, so "in december 2025"
        // is one window rather than a month window fighting a year window.
        return monthYear(lower, cal: cal)
            ?? rolling(lower, now: now, cal: cal)
            ?? relativeYear(lower, now: now, cal: cal)
            ?? month(lower, now: now, cal: cal)
            ?? season(lower, now: now, cal: cal)
            ?? absoluteYear(lower, cal: cal)
    }

    // MARK: - Grammar

    private static let monthNames = [
        "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december"
    ]

    /// Seasons as (firstMonth, monthCount). Winter starts in December, so it
    /// straddles the year boundary — handled where it is resolved.
    private static let seasons: [String: (start: Int, count: Int)] = [
        "winter": (12, 3), "spring": (3, 3), "summer": (6, 3),
        "fall": (9, 3), "autumn": (9, 3)
    ]

    private static let determiner = "(?:in|on|during|since|from|of|back in|around|last|this)"

    // Compiled once at first touch, following the precompiled-pack convention
    // the classifiers use (spec 029 Amendment A) — retrieval runs this on every
    // journal turn, and compiling six patterns per send is pure waste.
    private static let monthNamePattern = monthNames.joined(separator: "|")
    private static let seasonNamePattern = seasons.keys.sorted().joined(separator: "|")

    private static let monthYearRE = compile(#"\b(\#(monthNamePattern))\s+((?:19|20)\d\d)\b"#)
    private static let rollingRE = compile(#"\bthe\s+(?:last|past)\s+(?:(\d+|a|one|two|three|four|five|six|seven|eight|nine|ten|twelve)\s+)?(day|week|month|year)s?\b"#)
    private static let relativeYearRE = compile(#"\b(this|last)\s+year\b"#)
    private static let monthRE = compile(#"\b(\#(determiner))\s+(\#(monthNamePattern))\b"#)
    private static let seasonRE = compile(#"\b(\#(determiner))\s+(?:the\s+)?(\#(seasonNamePattern))\b"#)
    private static let absoluteYearRE = compile(#"\b((?:19|20)\d\d)\b"#)

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    /// "in december 2025", "december 2025"
    private static func monthYear(_ s: String, cal: Calendar) -> QueryDateWindow? {
        guard let (text, groups) = firstMatch(s, monthYearRE),
              let monthIndex = monthNames.firstIndex(of: groups[0]),
              let year = Int(groups[1]) else { return nil }
        return monthWindow(year: year, month: monthIndex + 1, cal: cal, text: text)
    }

    /// "the last six months", "the past year", "in the last 30 days"
    private static func rolling(_ s: String, now: Date, cal: Calendar) -> QueryDateWindow? {
        let words = ["a": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                     "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twelve": 12]
        guard let (text, groups) = firstMatch(s, rollingRE) else { return nil }
        let count = groups[0].isEmpty ? 1 : (Int(groups[0]) ?? words[groups[0]] ?? 1)
        let unit: Calendar.Component
        switch groups[1] {
        case "day": unit = .day
        case "week": unit = .weekOfYear
        case "month": unit = .month
        default: unit = .year
        }
        guard let start = cal.date(byAdding: unit, value: -count, to: now) else { return nil }
        return QueryDateWindow(start: start, end: now.addingTimeInterval(1), matchedText: text)
    }

    /// "this year", "last year" — calendar years, not rolling windows. The
    /// rolling grammar runs first, so "the last year" never reaches here.
    private static func relativeYear(_ s: String, now: Date, cal: Calendar) -> QueryDateWindow? {
        guard let (text, groups) = firstMatch(s, relativeYearRE) else { return nil }
        let year = cal.component(.year, from: now) - (groups[0] == "last" ? 1 : 0)
        guard let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
        return QueryDateWindow(start: start, end: end, matchedText: text)
    }

    /// "in december", "last december", "this march" — resolved to the most
    /// recent occurrence at or before now (`last` forces strictly before the
    /// current month, so "last december" in August 2026 is December 2025).
    private static func month(_ s: String, now: Date, cal: Calendar) -> QueryDateWindow? {
        guard let (text, groups) = firstMatch(s, monthRE),
              let monthIndex = monthNames.firstIndex(of: groups[1]) else { return nil }
        let month = monthIndex + 1
        let nowYear = cal.component(.year, from: now)
        let nowMonth = cal.component(.month, from: now)
        // The most recent occurrence at or before now, then one extra step back
        // only when `last` names the month we are currently in ("last august",
        // in August, is a year ago — but "last december", in August, is the
        // December four months back, not sixteen).
        var year = nowYear
        if month > nowMonth { year -= 1 }
        if groups[0] == "last" && month == nowMonth { year -= 1 }
        return monthWindow(year: year, month: month, cal: cal, text: text)
    }

    /// "this spring", "last winter", "in the summer". Winter is anchored on its
    /// December, so "last winter" in August 2026 is Dec 2025 – Feb 2026.
    private static func season(_ s: String, now: Date, cal: Calendar) -> QueryDateWindow? {
        guard let (text, groups) = firstMatch(s, seasonRE),
              let season = seasons[groups[1]] else { return nil }
        let nowYear = cal.component(.year, from: now)
        let nowMonth = cal.component(.month, from: now)

        // The year whose occurrence of this season most recently began.
        var year = nowYear
        if season.start > nowMonth { year -= 1 }
        if groups[0] == "last" {
            // Strictly the previous occurrence, unless the current one has not
            // begun yet — in which case the step back already happened above.
            if season.start <= nowMonth { year -= 1 }
        }
        guard let start = cal.date(from: DateComponents(year: year, month: season.start, day: 1)),
              let end = cal.date(byAdding: .month, value: season.count, to: start) else { return nil }
        return QueryDateWindow(start: start, end: end, matchedText: text)
    }

    /// A bare four-digit year — "what did I write about my brother in 2025".
    private static func absoluteYear(_ s: String, cal: Calendar) -> QueryDateWindow? {
        guard let (text, groups) = firstMatch(s, absoluteYearRE),
              let year = Int(groups[0]),
              let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return nil }
        return QueryDateWindow(start: start, end: end, matchedText: text)
    }

    // MARK: - Helpers

    private static func monthWindow(year: Int, month: Int, cal: Calendar, text: String) -> QueryDateWindow? {
        guard let start = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let end = cal.date(byAdding: .month, value: 1, to: start) else { return nil }
        return QueryDateWindow(start: start, end: end, matchedText: text)
    }

    /// First regex match, returning the whole matched span plus its capture
    /// groups (empty string for a group that did not participate).
    private static func firstMatch(_ s: String, _ regex: NSRegularExpression?) -> (text: String, groups: [String])? {
        guard let re = regex else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var groups: [String] = []
        for i in 1..<m.numberOfRanges {
            let r = m.range(at: i)
            groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
        }
        return (ns.substring(with: m.range), groups)
    }
}
