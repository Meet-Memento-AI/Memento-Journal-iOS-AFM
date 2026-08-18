import SwiftUI

public struct SummaryCard: View {
    // Inputs
    public let insights: [String]
    @State private var page: Int = 0

    // Environments
    @Environment(\.typography) private var type    // ← use canonical tokens
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(insights: [String]) {
        self.insights = insights
    }

    public var body: some View {
        let corner = theme.radius.xl
        let strokeOpacity = colorScheme == .dark ? 0.06 : 0.12

        VStack(spacing: 0) {
            // Header + Pages
            VStack(alignment: .leading, spacing: 16) {
                HeaderLabel()
                    .foregroundStyle(theme.foreground)

                // Swipeable pages
                TabView(selection: $page) {
                    ForEach(insights.indices, id: \.self) { idx in
                        InsightPage(text: insights[idx])
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Footer progress indicator
            ProgressSegments(current: page, total: insights.count)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            theme.card
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(theme.glassBorder.opacity(strokeOpacity / 0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12),
                radius: 12, x: 0, y: 6)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: page)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("AI Summary Card")
        .accessibilityValue("Page \(page + 1) of \(max(insights.count, 1))")
    }
}

// MARK: - Header

private struct HeaderLabel: View {
    @Environment(\.typography) private var type
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .bold)) // icon-size: not user text
                .imageScale(.small)
                .foregroundStyle(theme.accent)

            Text("AI SUMMARY")
                .font(type.labelBold)
                .modifier(type.lineSpacingModifier(for: type.sizeSM))
                .textCase(.uppercase)
                .kerning(0.6)
        }
    }
}

// MARK: - Page (H3 with line height of 1)

private struct InsightPage: View {
    let text: String
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        Text(text)
            .font(type.h3)
            .lineSpacing(0) // Line height of 1 (no extra spacing)
            .foregroundStyle(theme.foreground)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Segmented Progress (Footer)

private struct ProgressSegments: View {
    let current: Int
    let total: Int
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i == current ? theme.foreground : theme.mutedForeground.opacity(0.35))
                    .frame(height: 6)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(theme.glassBorder, lineWidth: 0.5)
                    )
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Preview
#Preview {
    ScrollView {
        VStack(spacing: 32) {
            SummaryCard(insights: [
                "Over the past week, you’ve reflected frequently on work stress and overwhelm around deadlines and meetings.",
                "You tend to feel better after short morning runs; consider scheduling two 20–30 minute sessions mid-week.",
                "One-on-one conversations leave you more energized than large group events."
            ])
        }
        .padding(.vertical, 24)
    }
    .useTypography(Typography(headingWeight: .semibold))
    .useTheme()
    .background(Color(.systemGroupedBackground))
}
