//
//  InsightEngine+Cadence.swift
//  MeetMemento
//
//  Week / month / streak / gap / hour facts. No FoundationModels.
//

import Foundation

extension InsightEngine {
    static func cadenceFacts(
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
        result.append(contentsOf: hourHistogramFacts(entries: entries, now: now, calendar: calendar))
        return result
    }

    static func streakFact(
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
        // n is the entry sample, not the day label — a 7-day streak of
        // two notes is still n < 4 / low-confidence (045 R1).
        return InsightFact(
            kind: .cadence,
            label: "Streak",
            value: length == 1 ? "1 day" : "\(length) days",
            n: ids.count,
            window: orderedInterval(start: start, end: end),
            supportingEntryIDs: ids
        )
    }

    static func longestGapFact(sorted: [Entry], calendar: Calendar) -> InsightFact? {
        guard sorted.count >= 2 else { return nil }
        var bestDays = 0
        var bestPair = (sorted[0], sorted[1])
        for index in 1..<sorted.count {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: sorted[index - 1].createdAt),
                to: calendar.startOfDay(for: sorted[index].createdAt)
            ).day ?? 0
            if days > bestDays {
                bestDays = days
                bestPair = (sorted[index - 1], sorted[index])
            }
        }
        let boundingIDs = [bestPair.0.id, bestPair.1.id]
        return InsightFact(
            kind: .cadence,
            label: "Longest gap",
            value: bestDays == 1 ? "1 day" : "\(bestDays) days",
            n: boundingIDs.count,
            window: orderedInterval(start: bestPair.0.createdAt, end: bestPair.1.createdAt),
            supportingEntryIDs: boundingIDs
        )
    }

    /// Occupied hours, busiest first. `n` is entries in that hour (045 R1).
    static func hourHistogramFacts(
        entries: [Entry], now: Date, calendar: Calendar
    ) -> [InsightFact] {
        guard !entries.isEmpty else { return [] }
        var buckets = [Int: [UUID]](minimumCapacity: 24)
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.createdAt)
            buckets[hour, default: []].append(entry.id)
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        let window = orderedInterval(
            start: entries.map(\.createdAt).min() ?? now,
            end: now.addingTimeInterval(1)
        )
        return buckets
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count {
                    return lhs.value.count > rhs.value.count
                }
                return lhs.key < rhs.key
            }
            .prefix(6) // budget-exempt: Patterns hour-histogram cap, not a model payload
            .map { hour, ids in
                var components = DateComponents()
                components.hour = hour
                let clock = calendar.date(from: components).map {
                    formatter.string(from: $0).lowercased()
                } ?? "\(hour)h"
                return InsightFact(
                    kind: .cadence,
                    label: "Around \(clock)",
                    value: "\(ids.count)",
                    n: ids.count,
                    window: window,
                    supportingEntryIDs: ids
                )
            }
    }
}
