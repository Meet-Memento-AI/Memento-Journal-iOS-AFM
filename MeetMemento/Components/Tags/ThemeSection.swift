//
//  ThemeSection.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 10/14/25.
//

import SwiftUI

// MARK: - Section

public struct ThemesSection: View {
    public let title: String
    public let themes: [String]

    // Tokens
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(title: String = "Your Themes", themes: [String]) {
        self.title = title
        self.themes = themes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(theme.primary)
                    .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                Text(title)
                    .font(type.body1Bold) // Manrope Bold 17 from Typography.swift
                    .modifier(type.lineSpacingModifier(for: type.sizeLG))
                    .foregroundStyle(theme.primary)
            }
            .padding(.horizontal, 4)

            // Wrapping tags
            TagFlowLayout(hSpacing: 8, vSpacing: 8) {
                ForEach(themes, id: \.self) { themeText in
                    ThemeTag(themeText)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Flow Layout (wraps children to new lines)

/// A lightweight wrapping layout for chips/tags. iOS 16+.
struct TagFlowLayout<Content: View>: View {
    let hSpacing: CGFloat
    let vSpacing: CGFloat
    @ViewBuilder var content: Content

    init(hSpacing: CGFloat = 4, vSpacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.hSpacing = hSpacing
        self.vSpacing = vSpacing
        self.content = content()
    }

    var body: some View {
        _TagFlowLayout(hSpacing: hSpacing, vSpacing: vSpacing) {
            content
        }
    }

    // Inner type that conforms to Layout for performance
    private struct _TagFlowLayout: Layout {
        let hSpacing: CGFloat
        let vSpacing: CGFloat

        init(hSpacing: CGFloat, vSpacing: CGFloat) {
            self.hSpacing = hSpacing
            self.vSpacing = vSpacing
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let maxWidth = proposal.width ?? .infinity
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x > 0 && x + size.width + hSpacing > maxWidth {
                    // next line
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
                    // wrap
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

// MARK: - Preview

#Preview("ThemesSection – Light") {
    ScrollView {
        ThemesSection(
            themes: [
                "Work-related stress", "Purpose",
                "Inner growth", "Closing doors",
                "Acceptance", "Realizing the truth",
                "Choosing better", "Living your life"
            ]
        )
        .padding(.top, 12)
    }
    .useTheme()
    .useTypography()
    .background(Color(.systemGroupedBackground))
}

#Preview("ThemesSection – Dark") {
    ScrollView {
        ThemesSection(
            themes: [
                "Work related stress", "Keeping an image",
                "Growing from within", "Closing doors",
                "Reaching acceptance", "Realizing the truth",
                "Choosing better", "Living your own life"
            ]
        )
        .padding(.top, 12)
    }
    .environment(\.colorScheme, .dark)
    .useTheme()
    .useTypography()
    .background(Color.black)
}
