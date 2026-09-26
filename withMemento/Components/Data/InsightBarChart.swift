//
//  InsightBarChart.swift
//  withMemento
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let occupied = facts.filter { $0.n > 0 }
        let maxCount = max(occupied.map(\.n).max() ?? 0, 1)
        let sparse = occupied.first { $0.isLowConfidence }

        if occupied.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Chart {
                    ForEach(Array(occupied.enumerated()), id: \.offset) { index, fact in
                        BarMark(
                            x: .value("Label", fact.label),
                            y: .value(yTitle, fact.n)
                        )
                        .foregroundStyle(barFill(index: index, lowConfidence: fact.isLowConfidence))
                        .clipShape(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
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

    /// Light cream → copper sheen. Mid-ramp highlights, not cordovan ink.
    private func barFill(index: Int, lowConfidence: Bool) -> LinearGradient {
        let pairs: [(Color, Color)] = colorScheme == .dark
            ? [
                (PrimaryScale.primary200, BrandColors.brandDark),
                (PrimaryScale.primary100, PrimaryScale.primary400),
                (PrimaryScale.primary200, PrimaryScale.primary400),
                (PrimaryScale.primary100, PrimaryScale.primary300),
                (PrimaryScale.primary300, BrandColors.brandDark)
            ]
            : [
                (PrimaryScale.primary100, PrimaryScale.primary300),
                (PrimaryScale.primary200, PrimaryScale.primary400),
                (PrimaryScale.primary200, BrandColors.brand),
                (PrimaryScale.primary100, PrimaryScale.primary400),
                (PrimaryScale.primary300, BrandColors.brand)
            ]
        let pair = pairs[index % pairs.count]
        let opacity = lowConfidence ? 0.55 : 1.0
        return LinearGradient(
            colors: [pair.0.opacity(opacity), pair.1.opacity(opacity)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
