//
//  InsightBarChart.swift
//  MeetMemento
//
//  Spec 045 R2: Swift Charts over InsightFact cadence. n stays on-device.
//

import Charts
import SwiftUI

struct InsightBarChart: View {
    let facts: [InsightFact]
    let yTitle: String
    let accessibilityLabel: String
    var chartHeight: CGFloat = 160

    @Environment(\.theme) private var theme

    var body: some View {
        let occupied = facts.filter { $0.n > 0 }
        let maxCount = max(occupied.map(\.n).max() ?? 0, 1)
        let sparse = occupied.first { $0.isLowConfidence }

        if occupied.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Chart {
                    ForEach(Array(occupied.enumerated()), id: \.offset) { _, fact in
                        BarMark(
                            x: .value("Label", fact.label),
                            y: .value(yTitle, fact.n)
                        )
                        .foregroundStyle(theme.chart1.opacity(fact.isLowConfidence ? 0.35 : 1))
                        .cornerRadius(6)
                        .annotation(position: .top, spacing: 4) {
                            Text("\(fact.n)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.mutedForeground)
                                .accessibilityLabel(InsightFact.sampleSizeCopy(n: fact.n))
                        }
                    }
                }
                .chartYScale(domain: 0 ... max(Int((Double(maxCount) * 1.25).rounded(.up)), 1))
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .foregroundStyle(theme.mutedForeground)
                    }
                }
                .chartYAxis(.hidden)
                .chartPlotStyle { plot in
                    plot.padding(.top, Spacing.md)
                }
                .frame(height: chartHeight)
                .accessibilityLabel(accessibilityLabel)

                if let sparse {
                    Text(InsightFact.lowConfidenceCopy(n: sparse.n))
                        .font(.caption)
                        .foregroundStyle(theme.mutedForeground)
                }
            }
        }
    }
}
