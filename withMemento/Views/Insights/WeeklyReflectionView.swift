//
//  WeeklyReflectionView.swift
//  withMemento
//
//  Spec 019 R3 / 045 R4: weekly reflection surface. Sample-size counts are
//  computed in Swift and shown in the UI — they are never sent to the model.
//

import SwiftUI

struct WeeklyReflectionView: View {
    @EnvironmentObject var entryViewModel: EntryViewModel
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @State private var isWriting = WeeklyReflectionStore.isWriting
    @State private var refreshStamp = Date()

    var body: some View {
        // swiftlint:disable:next redundant_discardable_let
        let _ = refreshStamp
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                let stats = PatternStats.week(entries: entryViewModel.entries)
                Text("This week")
                    .font(type.h3)
                Text("\(stats.entryCount) entries")
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .accessibilityIdentifier("weekly.entryCount")

                if isWriting {
                    Text("writing now…")
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                        .accessibilityIdentifier("weekly.writingNow")
                } else if WeeklyReflectionStore.hasNothingToSay,
                          WeeklyReflectionStore.latestBody != nil {
                    Text(WeeklyReflectionCoordinator.quietCopy)
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                        .accessibilityIdentifier("weekly.quiet")
                } else if let body = WeeklyReflectionStore.latestBody, !body.isEmpty {
                    Text(body)
                        .font(type.body1)
                    if let observation = WeeklyReflectionStore.observation, !observation.isEmpty {
                        Text(observation)
                            .font(type.body1.italic())
                            .padding(.top, Spacing.xs)
                    }
                    citationList
                    ratingRow
                } else {
                    Text(
                        "A weekly reflection appears here after you have a few entries. "
                            + "Counts stay on this screen — they are never sent to the model."
                    )
                    .font(type.body1)
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
        .onReceive(NotificationCenter.default.publisher(for: WeeklyReflectionStore.writingDidChange)) { _ in
            isWriting = WeeklyReflectionStore.isWriting
            refreshStamp = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: WeeklyReflectionStore.didSave)) { _ in
            isWriting = WeeklyReflectionStore.isWriting
            refreshStamp = Date()
        }
    }

    @ViewBuilder
    private var citationList: some View {
        let ids = WeeklyReflectionStore.citationIDs
        if !ids.isEmpty {
            Text("From your journal")
                .font(type.body1Medium)
                .padding(.top, Spacing.sm)
            ForEach(ids, id: \.self) { id in
                if let entry = entryViewModel.entry(id: id) {
                    NavigationLink(value: EntryRoute.edit(id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(type.body2)
                            Text(entry.excerpt)
                                .font(type.caption)
                                .foregroundStyle(theme.mutedForeground)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityIdentifier("weekly.citation.\(id.uuidString)")
                }
            }
        }
    }

    private var ratingRow: some View {
        HStack(spacing: Spacing.md) {
            Button {
                WeeklyReflectionStore.setRating(.up)
                refreshStamp = Date()
            } label: {
                Image(systemName: WeeklyReflectionStore.rating == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            .accessibilityIdentifier("weekly.thumbUp")
            Button {
                WeeklyReflectionStore.setRating(.down)
                refreshStamp = Date()
            } label: {
                Image(systemName: WeeklyReflectionStore.rating == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
            .accessibilityIdentifier("weekly.thumbDown")
        }
        .padding(.top, Spacing.sm)
    }
}

struct PatternsView: View {
    @EnvironmentObject var entryViewModel: EntryViewModel
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        let stats = PatternStats.month(entries: entryViewModel.entries)
        let moods = MementoDataStore.moodLabelsByEntry()
        let facts = InsightEngine.facts(entries: entryViewModel.entries, moodLabels: moods)
        let cadence = facts.filter { $0.kind == .cadence }
        let timeOfDay = InsightEngine.timeOfDayFacts(entries: entryViewModel.entries)
        let cadenceRows = cadence.filter {
            !$0.label.hasPrefix("Around ") && !InsightEngine.timeOfDayLabels.contains($0.label)
        }
        let people = facts.filter { $0.kind == .person }
        let places = facts.filter { $0.kind == .place }
        let clusters = facts.filter { $0.kind == .cluster }
        let valence = facts.filter { $0.kind == .valenceTrend }

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Patterns")
                    .font(type.h3)
                Text("\(stats.entryCount) entries this month")
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .opacity(stats.entryCount < InsightEngine.lowConfidenceThreshold ? 0.55 : 1)
                    .accessibilityIdentifier("patterns.entryCount")
                if stats.entryCount < InsightEngine.lowConfidenceThreshold {
                    Text(InsightFact.lowConfidenceCopy(n: stats.entryCount))
                        .font(type.caption)
                        .foregroundStyle(theme.mutedForeground)
                }

                if stats.weekFacts.contains(where: { $0.n > 0 }) {
                    Text("Entries by week")
                        .font(type.body1Medium)
                    InsightBarChart(
                        facts: stats.weekFacts,
                        yTitle: "Entries",
                        accessibilityLabel: "Entries per week this month"
                    )
                    .accessibilityIdentifier("patterns.chart")
                }

                if timeOfDay.contains(where: { $0.n > 0 }) {
                    Text("Time of day")
                        .font(type.body1Medium)
                    InsightBarChart(
                        facts: timeOfDay,
                        yTitle: "Entries",
                        accessibilityLabel: "Entries by time of day"
                    )
                    .accessibilityIdentifier("patterns.hourChart")
                }

                if !cadenceRows.isEmpty {
                    factList(title: "Cadence", facts: cadenceRows)
                }
                if !people.isEmpty {
                    factList(title: "People", facts: people)
                }
                if !places.isEmpty {
                    factList(title: "Places", facts: places)
                }
                if !valence.isEmpty {
                    factList(title: "Valence", facts: valence)
                }
                if !clusters.isEmpty {
                    KeywordsCard(facts: clusters)
                }

                Text("Charts are counted in the app. The model never sees these numbers.")
                    .font(type.caption)
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
                .font(type.body1Medium)
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(fact.label)
                            .font(type.body2)
                        Spacer()
                        Text(fact.value)
                            .font(type.body2Medium)
                    }
                    if fact.isLowConfidence {
                        Text(InsightFact.lowConfidenceCopy(n: fact.n))
                            .font(type.caption)
                            .foregroundStyle(theme.mutedForeground)
                    } else if fact.n > 0 {
                        Text(InsightFact.sampleSizeCopy(n: fact.n))
                            .font(type.caption)
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
                label: "Week \(index + 1)",
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
