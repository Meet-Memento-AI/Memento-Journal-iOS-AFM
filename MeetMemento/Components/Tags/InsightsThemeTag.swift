//
//  InsightsThemeTag.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/13/26.
//

import SwiftUI

/// A rounded tag component for displaying theme labels in the Insights view
/// Features a semi-transparent white background with subtle border on dark purple backgrounds
struct InsightsThemeTag: View {
    let text: String

    @Environment(\.typography) private var type
    @Environment(\.theme) private var theme

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(type.h6)
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(theme.muted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
    }
}

// MARK: - Previews

#Preview("Single Tag") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        InsightsThemeTag("Growth mindset")
            .padding()
    }
    .useTypography()
}

#Preview("Multiple Tags") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        VStack(spacing: 16) {
            HStack(spacing: 12) {
                InsightsThemeTag("Self-discovery")
                InsightsThemeTag("Resilience")
            }

            HStack(spacing: 12) {
                InsightsThemeTag("Work-life balance")
                InsightsThemeTag("Growth")
            }

            HStack(spacing: 12) {
                InsightsThemeTag("Mindfulness")
                InsightsThemeTag("Identity")
                InsightsThemeTag("Purpose")
            }
        }
        .padding()
    }
    .useTypography()
}

#Preview("Wrapped Tags") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        ScrollView {
            FlowLayout(spacing: 12) {
                InsightsThemeTag("Personal growth")
                InsightsThemeTag("Self-reflection")
                InsightsThemeTag("Emotional awareness")
                InsightsThemeTag("Work stress")
                InsightsThemeTag("Identity")
                InsightsThemeTag("Purpose")
                InsightsThemeTag("Acceptance")
                InsightsThemeTag("Resilience")
            }
            .padding()
        }
    }
    .useTypography()
}

// MARK: - Flow Layout Helper

/// Simple flow layout for wrapping tags
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    // Move to next line
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
