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
                    Text("A weekly reflection appears here after you have a few entries. Counts stay on this screen — they are never sent to the model.")
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
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                let stats = PatternStats.month(entries: entryViewModel.entries)
                Text("Patterns")
                    .font(.title2.weight(.semibold))
                Text("\(stats.entryCount) entries this month")
                    .font(.subheadline)
                    .foregroundStyle(theme.mutedForeground)
                    .accessibilityIdentifier("patterns.entryCount")

                PatternCountChart(weeks: stats.weeklyCounts)
                    .frame(height: 160)
                    .accessibilityIdentifier("patterns.chart")

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
}

struct PatternStats: Equatable {
    let entryCount: Int
    let weeklyCounts: [Int]

    static func week(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> PatternStats {
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let count = entries.filter { $0.createdAt >= start }.count
        return PatternStats(entryCount: count, weeklyCounts: [count])
    }

    static func month(entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> PatternStats {
        let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let inMonth = entries.filter { $0.createdAt >= start }
        var buckets = Array(repeating: 0, count: 5)
        for entry in inMonth {
            let week = min(4, calendar.component(.weekOfMonth, from: entry.createdAt) - 1)
            if week >= 0 { buckets[week] += 1 }
        }
        return PatternStats(entryCount: inMonth.count, weeklyCounts: buckets)
    }
}

struct PatternCountChart: View {
    let weeks: [Int]
    @Environment(\.theme) private var theme

    var body: some View {
        let maxValue = max(weeks.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, value in
                VStack {
                    Capsule()
                        .fill(theme.foreground.opacity(0.7))
                        .frame(width: 22, height: max(8, CGFloat(value) / CGFloat(maxValue) * 120))
                    Text("W\(index + 1)")
                        .font(.caption2)
                        .foregroundStyle(theme.mutedForeground)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityLabel("Entries per week this month")
    }
}
