//
//  WeeklyReflectionView.swift
//  MeetMemento
//
//  Spec 019 R3: weekly reflection surface. Sample-size counts are computed
//  in Swift and shown in the UI — they are never sent to the model (037).
//

import SwiftUI

struct WeeklyReflectionView: View {
    @EnvironmentObject var entryViewModel: EntryViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                let stats = PatternStats.week(entries: entryViewModel.entries)
                Text("This week")
                    .font(.title2.weight(.semibold))
                Text("\(stats.entryCount) entries")
                    .font(.subheadline)
                    .foregroundStyle(theme.mutedForeground)
                    .accessibilityIdentifier("weekly.entryCount")

                if let body = WeeklyReflectionStore.latestBody, !body.isEmpty {
                    Text(body)
                        .font(.body)
                } else {
                    Text(
                        "A weekly reflection appears here after you have a few entries. "
                            + "Counts stay on this screen — they are never sent to the model."
                    )
                        .font(.body)
                        .foregroundStyle(theme.mutedForeground)
                }
                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Weekly")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PatternsView: View {
    @EnvironmentObject var entryViewModel: EntryViewModel
    @Environment(\.theme) private var theme

    var body: some View {
        let stats = PatternStats.month(entries: entryViewModel.entries)
        let facts = InsightEngine.facts(entries: entryViewModel.entries)
        let cadence = facts.filter { $0.kind == .cadence }
        let people = facts.filter { $0.kind == .person }
        let places = facts.filter { $0.kind == .place }
        let clusters = facts.filter { $0.kind == .cluster }

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Patterns")
                    .font(.title2.weight(.semibold))
                Text("\(stats.entryCount) entries this month")
                    .font(.subheadline)
                    .foregroundStyle(theme.mutedForeground)
                    .opacity(stats.entryCount < InsightEngine.lowConfidenceThreshold ? 0.55 : 1)
                    .accessibilityIdentifier("patterns.entryCount")
                if stats.entryCount < InsightEngine.lowConfidenceThreshold {
                    Text(InsightFact.lowConfidenceCopy(n: stats.entryCount))
                        .font(.caption)
                        .foregroundStyle(theme.mutedForeground)
                }

                PatternCountChart(facts: stats.weekFacts)
                    .frame(height: 160)
                    .accessibilityIdentifier("patterns.chart")

                if !cadence.isEmpty {
                    factList(title: "Cadence", facts: cadence)
                }
                if !people.isEmpty {
                    factList(title: "People", facts: people)
                }
                if !places.isEmpty {
                    factList(title: "Places", facts: places)
                }
                if !clusters.isEmpty {
                    KeywordsCard(facts: clusters)
                }

                Text("Charts are counted in the app. The model never sees these numbers.")
                    .font(.footnote)
                    .foregroundStyle(theme.mutedForeground)
                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.md)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Patterns")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func factList(title: String, facts: [InsightFact]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.headline)
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(fact.label)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(fact.value)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text("n = \(fact.n)")
                        .font(.caption)
                        .foregroundStyle(theme.mutedForeground)
                    if fact.isLowConfidence {
                        Text(InsightFact.lowConfidenceCopy(n: fact.n))
                            .font(.caption)
                            .foregroundStyle(theme.mutedForeground)
                    }
                }
                .opacity(fact.isLowConfidence ? 0.55 : 1)
            }
        }
    }
}

struct PatternStats: Equatable {
    let entryCount: Int
    let weeklyCounts: [Int]
    /// Per-week cadence facts for the Patterns chart. `n` is unique entries
    /// in that week-of-month; `n < 4` greys the bar (045 R2).
    let weekFacts: [InsightFact]

    static func week(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> PatternStats {
        let fact = InsightEngine.weekCadence(entries: entries, containing: now, calendar: calendar)
        return PatternStats(entryCount: fact.n, weeklyCounts: [fact.n], weekFacts: [fact])
    }

    static func month(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> PatternStats {
        let fact = InsightEngine.monthCadence(entries: entries, containing: now, calendar: calendar)
        let inMonth = entries.filter { fact.window.contains($0.createdAt) }
        var buckets = Array(repeating: [Entry](), count: 5)
        for entry in inMonth {
            let week = min(4, calendar.component(.weekOfMonth, from: entry.createdAt) - 1)
            if week >= 0 { buckets[week].append(entry) }
        }
        let weekFacts = buckets.enumerated().map { index, hits in
            InsightFact(
                kind: .cadence,
                label: "W\(index + 1)",
                value: "\(hits.count)",
                n: hits.count,
                window: fact.window,
                supportingEntryIDs: hits.map(\.id)
            )
        }
        return PatternStats(
            entryCount: fact.n,
            weeklyCounts: weekFacts.map(\.n),
            weekFacts: weekFacts
        )
    }
}

struct PatternCountChart: View {
    let facts: [InsightFact]
    @Environment(\.theme) private var theme

    var body: some View {
        let weeks = facts.map(\.n)
        let maxValue = max(weeks.max() ?? 0, 1)
        let sparse = facts.first { $0.n > 0 && $0.isLowConfidence }
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .bottom, spacing: Spacing.sm) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    VStack {
                        Text("n = \(fact.n)")
                            .font(.caption2)
                            .foregroundStyle(theme.mutedForeground)
                        Capsule()
                            .fill(theme.foreground.opacity(fact.isLowConfidence ? 0.35 : 0.7))
                            .frame(width: 22, height: max(8, CGFloat(fact.n) / CGFloat(maxValue) * 120))
                        Text(fact.label)
                            .font(.caption2)
                            .foregroundStyle(theme.mutedForeground)
                    }
                    .opacity(fact.isLowConfidence ? 0.55 : 1)
                    .frame(maxWidth: .infinity)
                }
            }
            if let sparse {
                Text(InsightFact.lowConfidenceCopy(n: sparse.n))
                    .font(.caption)
                    .foregroundStyle(theme.mutedForeground)
            }
        }
        .accessibilityLabel("Entries per week this month")
    }
}
