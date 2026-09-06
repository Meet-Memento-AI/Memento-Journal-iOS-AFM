//
//  InsightEngine.swift
//  MeetMemento
//
//  Spec 045 R1: cadence, people/places, clusters — arithmetic only.
//  No `import FoundationModels`.
//

import Foundation
import NaturalLanguage

enum InsightEngine {
    static let lowConfidenceThreshold = 4

    private static let stopwords: Set<String> = [
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

    // MARK: - Patterns corpus

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

    // MARK: - Quantitative Ask

    /// Answer a count / how-often / last-mention question. Empty when no
    /// subject can be extracted.
    static func answer(
        query: String,
        entries: [Entry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [InsightFact] {
        let window = QueryDateWindowParser.parse(query, now: now, calendar: calendar)
        let interval = window.map { DateInterval(start: $0.start, end: $0.end) }
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
                    excerpt: String(entry.text.prefix(160))
                ))
            }
        }
        return result
    }

    // MARK: - Cadence

    private static func cadenceFacts(
        entries: [Entry], now: Date, calendar: Calendar
    ) -> [InsightFact] {
        var result: [InsightFact] = []
        result.append(weekCadence(entries: entries, containing: now, calendar: calendar))
        result.append(monthCadence(entries: entries, containing: now, calendar: calendar))

        let sorted = entries.sorted { $0.createdAt < $1.createdAt }
        if let streak = streakFact(sorted: sorted, now: now, calendar: calendar) {
            result.append(streak)
        }
        if let gap = longestGapFact(sorted: sorted, calendar: calendar) {
            result.append(gap)
        }
        if let hour = peakHourFact(entries: entries, now: now, calendar: calendar) {
            result.append(hour)
        }
        return result
    }

    private static func streakFact(
        sorted: [Entry], now: Date, calendar: Calendar
    ) -> InsightFact? {
        guard !sorted.isEmpty else { return nil }
        let days = Set(sorted.map { calendar.startOfDay(for: $0.createdAt) })
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        var length = 0
        var ids: [UUID] = []
        while days.contains(cursor) {
            length += 1
            ids += sorted.filter { calendar.isDate($0.createdAt, inSameDayAs: cursor) }.map(\.id)
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        let end = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        let start = calendar.date(byAdding: .day, value: -max(length, 1), to: end) ?? end
        return InsightFact(
            kind: .cadence,
            label: "Streak",
            value: length == 1 ? "1 day" : "\(length) days",
            n: length,
            window: DateInterval(start: start, end: end),
            supportingEntryIDs: ids
        )
    }

    private static func longestGapFact(sorted: [Entry], calendar: Calendar) -> InsightFact? {
        guard sorted.count >= 2 else { return nil }
        var bestDays = 0
        var bestPair = (sorted[0], sorted[1])
        for index in 1..<sorted.count {
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: sorted[index - 1].createdAt),
                to: calendar.startOfDay(for: sorted[index].createdAt)
            ).day ?? 0
            if days > bestDays {
                bestDays = days
                bestPair = (sorted[index - 1], sorted[index])
            }
        }
        return InsightFact(
            kind: .cadence,
            label: "Longest gap",
            value: bestDays == 1 ? "1 day" : "\(bestDays) days",
            n: bestDays,
            window: DateInterval(start: bestPair.0.createdAt, end: bestPair.1.createdAt),
            supportingEntryIDs: [bestPair.0.id, bestPair.1.id]
        )
    }

    private static func peakHourFact(
        entries: [Entry], now: Date, calendar: Calendar
    ) -> InsightFact? {
        guard !entries.isEmpty else { return nil }
        var buckets = [Int: [UUID]](minimumCapacity: 24)
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.createdAt)
            buckets[hour, default: []].append(entry.id)
        }
        guard let peak = buckets.max(by: { $0.value.count < $1.value.count }) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = peak.key
        let labelHour = calendar.date(from: components).map { formatter.string(from: $0).lowercased() } ?? "\(peak.key)h"
        return InsightFact(
            kind: .cadence,
            label: "Most often around",
            value: labelHour,
            n: peak.value.count,
            window: DateInterval(start: entries.map(\.createdAt).min() ?? now, end: now),
            supportingEntryIDs: peak.value
        )
    }

    // MARK: - People / places

    private static func namedEntityFacts(
        entries: [Entry], now: Date, calendar: Calendar
    ) -> [InsightFact] {
        var people: [String: [Entry]] = [:]
        var places: [String: [Entry]] = [:]
        let tagger = NLTagger(tagSchemes: [.nameType])
        for entry in entries {
            let blob = entry.title + " " + entry.text
            tagger.string = blob
            tagger.enumerateTags(
                in: blob.startIndex..<blob.endIndex,
                unit: .word,
                scheme: .nameType,
                options: [.omitWhitespace, .omitPunctuation, .joinNames]
            ) { tag, range in
                guard let tag else { return true }
                let name = String(blob[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.count >= 2 else { return true }
                switch tag {
                case .personalName:
                    people[name, default: []].append(entry)
                case .placeName:
                    places[name, default: []].append(entry)
                default:
                    break
                }
                return true
            }
        }
        let window = DateInterval(
            start: entries.map(\.createdAt).min() ?? now,
            end: now.addingTimeInterval(1)
        )
        let personFacts = people
            .sorted { $0.value.count > $1.value.count }
            .prefix(8)
            .map { name, hits in
                InsightFact(
                    kind: .person,
                    label: name,
                    value: namedEntityValue(hits),
                    n: hits.count,
                    window: window,
                    supportingEntryIDs: hits.map(\.id)
                )
            }
        let placeFacts = places
            .sorted { $0.value.count > $1.value.count }
            .prefix(8)
            .map { name, hits in
                InsightFact(
                    kind: .place,
                    label: name,
                    value: namedEntityValue(hits),
                    n: hits.count,
                    window: window,
                    supportingEntryIDs: hits.map(\.id)
                )
            }
        return Array(personFacts) + Array(placeFacts)
    }

    private static func namedEntityValue(_ hits: [Entry]) -> String {
        let dates = hits.map(\.createdAt).sorted()
        guard let first = dates.first, let last = dates.last else { return "\(hits.count)" }
        if first == last {
            return "\(hits.count) · \(EntryRetriever.formattedDate(first))"
        }
        return "\(hits.count) · \(EntryRetriever.formattedDate(first))–\(EntryRetriever.formattedDate(last))"
    }

    // MARK: - Clusters

    /// Greedy groups over cached whole-entry vectors. Empty when NLEmbedding
    /// is unavailable (CI).
    private static func clusterFacts(
        entries: [Entry], now: Date, calendar: Calendar
    ) -> [InsightFact] {
        let service = EmbeddingService.shared
        var vectors: [(Entry, [Double], Double)] = []
        for entry in entries {
            let hash = EmbeddingService.contentHash(title: entry.title, text: entry.text)
            if let cached = service.cachedEntryVector(id: entry.id, contentHash: hash) {
                vectors.append((entry, cached.vector, cached.norm))
            }
        }
        guard vectors.count >= 3 else { return [] }

        var clusters: [[(Entry, [Double], Double)]] = []
        for item in vectors {
            var best = -1
            var bestCosine = 0.82
            for (index, cluster) in clusters.enumerated() {
                let mean = averageCosine(item, cluster: cluster)
                if mean > bestCosine {
                    bestCosine = mean
                    best = index
                }
            }
            if best >= 0 {
                clusters[best].append(item)
            } else {
                clusters.append([item])
            }
        }

        let window = DateInterval(
            start: entries.map(\.createdAt).min() ?? now,
            end: now.addingTimeInterval(1)
        )
        let corpusTokens = vectors.map { tokens($0.0.title + " " + $0.0.text) }
        let documentFrequency = idfDocumentFrequency(corpusTokens)
        let corpusSize = Double(max(corpusTokens.count, 1))
        return clusters
            .filter { $0.count >= 2 }
            .sorted { $0.count > $1.count }
            .prefix(6)
            .map { cluster in
                let members = cluster.map(\.0)
                let label = clusterLabel(members, documentFrequency: documentFrequency, corpusSize: corpusSize)
                return InsightFact(
                    kind: .cluster,
                    label: label,
                    value: "\(members.count)",
                    n: members.count,
                    window: window,
                    supportingEntryIDs: members.map(\.id)
                )
            }
    }

    private static func averageCosine(
        _ item: (Entry, [Double], Double),
        cluster: [(Entry, [Double], Double)]
    ) -> Double {
        let sum = cluster.reduce(0.0) { partial, other in
            partial + EmbeddingService.cosineSimilarity(
                item.1, normA: item.2, other.1, normB: other.2
            )
        }
        return sum / Double(cluster.count)
    }

    private static func idfDocumentFrequency(_ corpusTokens: [[String]]) -> [String: Int] {
        var df: [String: Int] = [:]
        for entryTokens in corpusTokens {
            for token in Set(entryTokens) {
                df[token, default: 0] += 1
            }
        }
        return df
    }

    private static func clusterLabel(
        _ entries: [Entry],
        documentFrequency: [String: Int],
        corpusSize: Double
    ) -> String {
        var tf: [String: Int] = [:]
        for entry in entries {
            for token in tokens(entry.title + " " + entry.text) {
                tf[token, default: 0] += 1
            }
        }
        let ranked = tf.map { token, count -> (String, Double) in
            let df = Double(documentFrequency[token] ?? 1)
            let idf = log((corpusSize + 1) / (df + 1)) + 1
            return (token, Double(count) * idf)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(2)
        .map(\.0)
        return ranked.isEmpty ? "Related entries" : ranked.joined(separator: " · ")
    }

    // MARK: - Subject matching

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

    // MARK: - Helpers

    private static func isoCalendar(_ calendar: Calendar) -> Calendar {
        if calendar.identifier == .iso8601 { return calendar }
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        return iso
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count > 2 && !stopwords.contains($0) }
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
