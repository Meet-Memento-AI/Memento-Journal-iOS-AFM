//
//  KeywordsCard.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/13/26.
//

import SwiftUI

/// Cluster / keyword chips for the Patterns tab. Section chrome shows `n`;
/// low-confidence chips (`n < 4`) render grey.
struct KeywordsCard: View {
    struct Chip: Hashable, Identifiable {
        var id: String { "\(text)|\(n)" }
        let text: String
        let n: Int
        var isLowConfidence: Bool { n < InsightEngine.lowConfidenceThreshold }
    }

    let chips: [Chip]
    var title: String = "CLUSTERS"

    init(facts: [InsightFact], title: String = "CLUSTERS") {
        self.chips = facts.map { Chip(text: $0.label, n: $0.n) }
        self.title = title
    }

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(type.body2Bold)
                    .foregroundStyle(theme.accent)

                Text(title)
                    .font(type.captionBold)
                    .tracking(0.5)
                    .foregroundStyle(theme.foreground)

                Spacer()
                let n = chips.reduce(0) { $0 + $1.n }
                if n > 0 {
                    Text("n = \(n)")
                        .font(type.captionBold)
                        .foregroundStyle(theme.mutedForeground)
                }
            }

            InsightsTagFlowLayout(hSpacing: 12, vSpacing: 12) {
                ForEach(chips) { chip in
                    InsightsThemeTag(
                        chip.n > 0 ? "\(chip.text) · \(chip.n)" : chip.text,
                        isLowConfidence: chip.isLowConfidence && chip.n > 0
                    )
                }
            }
        }
        .padding(24)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout Helper

/// A lightweight wrapping layout for keywords/tags
private struct InsightsTagFlowLayout<Content: View>: View {
    let hSpacing: CGFloat
    let vSpacing: CGFloat
    @ViewBuilder var content: Content

    init(hSpacing: CGFloat = 4, vSpacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
        self.content = content()
    }

    var body: some View {
        _InsightsTagFlowLayout(hSpacing: hSpacing, vSpacing: vSpacing) {
            content
        }
    }

    private struct _InsightsTagFlowLayout: Layout {
        let hSpacing: CGFloat
        let vSpacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x > 0 && x + size.width + hSpacing > maxWidth {
                    x = 0
                    y += rowHeight + vSpacing
                    rowHeight = 0
                }
                rowHeight = max(rowHeight, size.height)
                if x > 0 { x += hSpacing }
                x += size.width
            }
            return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let maxWidth = bounds.width
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for (index, subview) in subviews.enumerated() {
                let size = subview.sizeThatFits(.unspecified)

                if x > 0 && x + size.width + hSpacing > maxWidth {
                    x = 0
                    y += rowHeight + vSpacing
                    rowHeight = 0
                }

                let origin = CGPoint(x: bounds.minX + x, y: bounds.minY + y)
                subview.place(at: origin, proposal: ProposedViewSize(width: size.width, height: size.height))

                rowHeight = max(rowHeight, size.height)
                if index < subviews.count - 1 { x += size.width + hSpacing }
                else { x += size.width }
            }
        }
    }
}
