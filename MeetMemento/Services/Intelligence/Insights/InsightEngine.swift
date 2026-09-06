//
//  InsightEngine.swift
//  MeetMemento
//
//  Spec 045 R1: cadence, people/places, clusters — arithmetic only.
//  No `import FoundationModels`.
//

import Foundation

enum InsightEngine {
    static let lowConfidenceThreshold = 4

    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "if", "then", "so", "to", "of", "in",
        "on", "at", "for", "with", "about", "as", "is", "are", "was", "were", "be",
        "been", "being", "do", "did", "does", "have", "has", "had", "i", "you", "me",
        "my", "your", "it", "this", "that", "what", "when", "where", "why", "how",
        "can", "could", "would", "should", "will", "just", "really", "very", "am",
        "many", "times", "time", "often", "last", "write", "writes", "wrote", "written",
        "mention", "mentions", "mentioned", "say", "said", "feel", "felt", "changed",
        "shifted", "change", "shift", "past", "year", "month", "week", "day", "days",
        "entries", "entry", "journal", "lately", "recently"
    ]

    /// Cadence + people + places + clusters for the Patterns tab.
    static func facts(
        entries: [Entry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [InsightFact] {
        var result: [InsightFact] = []
        result.append(contentsOf: cadenceFacts(entries: entries, now: now, calendar: calendar))
        result.append(contentsOf: namedEntityFacts(entries: entries, now: now, calendar: calendar))
        result.append(contentsOf: clusterFacts(entries: entries, now: now, calendar: calendar))
        return result
    }

    /// Cadence for the ISO week containing `date` (sparse-week goldens).
    static func weekCadence(
        entries: [Entry],
        containing date: Date,
        calendar: Calendar = Calendar(identifier: .iso8601)
    ) -> InsightFact {
        let cal = isoCalendar(calendar)
        let interval = cal.dateInterval(of: .weekOfYear, for: date)
            ?? DateInterval(start: date, duration: 7 * 86_400)
        let hits = entries.filter { interval.contains($0.createdAt) }
        return InsightFact(
            kind: .cadence,
            label: "This week",
            value: "\(hits.count)",
            n: hits.count,
            window: interval,
            supportingEntryIDs: hits.map(\.id)
        )
    }

    static func monthCadence(
        entries: [Entry],
        containing date: Date,
        calendar: Calendar = .current
    ) -> InsightFact {
        let interval = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: date, duration: 30 * 86_400)
        let hits = entries.filter { interval.contains($0.createdAt) }
        return InsightFact(
            kind: .cadence,
            label: "This month",
            value: "\(hits.count)",
            n: hits.count,
            window: interval,
            supportingEntryIDs: hits.map(\.id)
        )
    }

    /// Answer a count / how-often / last-mention question. Empty when no
    /// subject can be extracted.
    static func answer(
        query: String,
        entries: [Entry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [InsightFact] {
        let window = QueryDateWindowParser.parse(query, now: now, calendar: calendar)
        let interval = window.map { orderedInterval(start: $0.start, end: $0.end) }
            ?? relativePeriodInterval(query, now: now, calendar: calendar)
            ?? DateInterval(start: .distantPast, end: now.addingTimeInterval(1))
        let pool = entries.filter { interval.contains($0.createdAt) }
        let subject = extractSubject(query, window: window)
        let wantsLast = isLastMentionQuery(query)

        if subject.isEmpty {
            let hits = pool
            if wantsLast, let last = hits.max(by: { $0.createdAt < $1.createdAt }) {
                return [lastMentionFact(entry: last, hits: hits, label: "an entry", window: interval)]
            }
            return [countFact(hits: hits, label: "entries", window: interval)]
        }

        let hits = pool.filter { containsSubject($0, subject) }
        if wantsLast {
            guard let last = hits.max(by: { $0.createdAt < $1.createdAt }) else {
                return [InsightFact(
                    kind: .lastMention,
                    label: subject,
                    value: "Not in this stretch",
                    n: 0,
                    window: interval,
                    supportingEntryIDs: []
                )]
            }
            return [lastMentionFact(entry: last, hits: hits, label: subject, window: interval)]
        }
        return [countFact(hits: hits, label: subject, window: interval)]
    }

    static func citations(for facts: [InsightFact], entries: [Entry]) -> [AskCitation] {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        var seen = Set<UUID>()
        var result: [AskCitation] = []
        for fact in facts {
            for id in fact.supportingEntryIDs where seen.insert(id).inserted {
                guard let entry = byID[id] else { continue }
                result.append(AskCitation(
                    entryId: entry.id,
                    entryDate: entry.createdAt,
                    excerpt: String(entry.text.prefix(160)) // budget-exempt: citation preview, not a model payload
                ))
            }
        }
        return result
    }

    static func extractSubject(_ query: String, window: QueryDateWindow?) -> String {
        let lower = query.lowercased()
        let about = compile(#"(?:about|mention(?:ed|s)?|wrote about|written about|write about)\s+(?:my\s+)?([a-z][a-z'-]+)"#)
        if let match = firstGroup(lower, about) { return match }
        var terms = tokens(lower)
        if let window {
            let dateWords = Set(tokens(window.matchedText))
            terms.removeAll { dateWords.contains($0) }
        }
        return terms.first ?? ""
    }

    static func containsSubject(_ entry: Entry, _ subject: String) -> Bool {
        let hay = (entry.title + " " + entry.text).lowercased()
        if EntryRetriever.containsWord(hay, subject) { return true }
        if subject.hasSuffix("s") {
            return EntryRetriever.containsWord(hay, String(subject.dropLast()))
        }
        return EntryRetriever.containsWord(hay, subject + "s")
    }

    static func isoCalendar(_ calendar: Calendar) -> Calendar {
        if calendar.identifier == .iso8601 { return calendar }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        return iso
    }

    /// `DateInterval(start:end:)` traps when `end < start`. Patterns and Ask
    /// can see a pinned `now` before the newest entry (or a future-dated one).
    static func orderedInterval(start: Date, end: Date) -> DateInterval {
        start <= end
            ? DateInterval(start: start, end: end)
            : DateInterval(start: end, end: start)
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count > 2 && !stopwords.contains($0) }
    }

    private static func isLastMentionQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        return lower.contains("last mention")
            || lower.contains("last time")
            || lower.contains("when did i last")
            || lower.contains("when was the last")
    }

    private static func countFact(hits: [Entry], label: String, window: DateInterval) -> InsightFact {
        InsightFact(
            kind: .count,
            label: label,
            value: "\(hits.count)",
            n: hits.count,
            window: window,
            supportingEntryIDs: hits.map(\.id)
        )
    }

    private static func lastMentionFact(
        entry: Entry, hits: [Entry], label: String, window: DateInterval
    ) -> InsightFact {
        InsightFact(
            kind: .lastMention,
            label: label,
            value: EntryRetriever.formattedDate(entry.createdAt),
            n: hits.count,
            window: window,
            supportingEntryIDs: hits.map(\.id)
        )
    }

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func firstGroup(_ text: String, _ regex: NSRegularExpression?) -> String? {
        guard let regex else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }
}

extension InsightEngine {
    /// "this month" / "last week" are not in `QueryDateWindowParser` (named
    /// months and "this year" only). Phase II starters need them so Swift `n`
    /// is not the whole corpus.
    static func relativePeriodInterval(
        _ query: String, now: Date, calendar: Calendar
    ) -> DateInterval? {
        let lower = query.lowercased()
        if lower.contains("this week") {
            return calendar.dateInterval(of: .weekOfYear, for: now).map {
                orderedInterval(start: $0.start, end: $0.end)
            }
        }
        if lower.contains("last week"),
           let cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: now) {
            return calendar.dateInterval(of: .weekOfYear, for: cursor).map {
                orderedInterval(start: $0.start, end: $0.end)
            }
        }
        if lower.contains("this month") {
            return calendar.dateInterval(of: .month, for: now).map {
                orderedInterval(start: $0.start, end: $0.end)
            }
        }
        if lower.contains("last month"),
           let cursor = calendar.date(byAdding: .month, value: -1, to: now) {
            return calendar.dateInterval(of: .month, for: cursor).map {
                orderedInterval(start: $0.start, end: $0.end)
            }
        }
        return nil
    }
}
}
