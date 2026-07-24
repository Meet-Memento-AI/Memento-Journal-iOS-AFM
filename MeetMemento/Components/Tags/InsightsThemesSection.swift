import SwiftUI

/// Themes section specifically styled for Insights view (white on purple background)
public struct InsightsThemesSection: View {
    public let themes: [String]

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(themes: [String]) {
        self.themes = themes
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with icon
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(theme.overlayText)

                Text("Your Themes")
                    .font(type.h6)
                    .foregroundStyle(theme.overlayText)
            }

            // Wrapping tags
            InsightsTagFlowLayout(hSpacing: 12, vSpacing: 12) {
                ForEach(themes, id: \.self) { themeText in
                    InsightsThemeTag(themeText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Flow Layout (wraps children to new lines)

/// A lightweight wrapping layout for chips/tags. iOS 16+.
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

    // Inner type that conforms to Layout for performance
    private struct _InsightsTagFlowLayout: Layout {
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

#Preview {
    ZStack {
        // Purple gradient background to match Insights view
        LinearGradient(
            gradient: Gradient(colors: [
                PrimaryScale.primary800,
                PrimaryScale.primary700
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ScrollView {
            InsightsThemesSection(
                themes: [
                    "Work related stress",
                    "Keeping an image",
                    "Growing from within",
                    "Closing doors",
                    "Reaching acceptance",
                    "Realizing the truth",
                    "Choosing better",
                    "Living your own life"
                ]
            )
            .padding(20)
        }
    }
    .useTheme()
    .useTypography()
}
