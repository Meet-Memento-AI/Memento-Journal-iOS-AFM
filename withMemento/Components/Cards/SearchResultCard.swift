//
//  SearchResultCard.swift
//  MeetMemento
//
//  Lightweight card for displaying search results in journal search
//

import SwiftUI

struct SearchResultCard: View {
    // MARK: - Inputs
    let title: String
    let excerpt: String
    let date: Date
    var onTap: (() -> Void)? = nil

    // MARK: - Environment
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // MARK: - State
    @State private var isPressed = false

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Title
            Text(title)
                .typographyH5()
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Excerpt
            Text(excerpt)
                .typographyBody2()
                .foregroundStyle(theme.mutedForeground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Date
            Text(formattedDate)
                .typographyCaption()
                .foregroundStyle(theme.mutedForeground)
        }
        .padding(Spacing.md)
        .cardStyle(radius: theme.radius.lg, border: false, shadow: false, backgroundColor: theme.secondary)
        .pressEffect(isPressed: $isPressed, scale: 0.98, duration: Spacing.Duration.fast)
        .contentShape(Rectangle())
        .onTapGesture {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Search result: \(title). \(excerpt). \(formattedDate)")
        .accessibilityHint("Double tap to open entry")
    }

    // MARK: - Date Formatting
    private var formattedDate: String {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM"
        let monthName = monthFormatter.string(from: date)

        return "\(monthName) \(day)\(ordinalSuffix(for: day))"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31:
            return "st"
        case 2, 22:
            return "nd"
        case 3, 23:
            return "rd"
        default:
            return "th"
        }
    }
}

// MARK: - Previews

#Preview("SearchResultCard - Light") {
    VStack(spacing: Spacing.md) {
        SearchResultCard(
            title: "Morning Reflection",
            excerpt: "I woke up feeling a bit groggy and not entirely refreshed. The alarm felt harsh...",
            date: Date()
        )

        SearchResultCard(
            title: "Weekly Review",
            excerpt: "What went well: shipped UI preview harnesses, stabilized Xcode canvas.",
            date: Date().addingTimeInterval(-86400 * 3)
        )
    }
    .padding()
    .background(Environment(\.theme).wrappedValue.background)
    .useTheme()
    .useTypography()
}

#Preview("SearchResultCard - Dark") {
    VStack(spacing: Spacing.md) {
        SearchResultCard(
            title: "Evening Thoughts",
            excerpt: "Today was productive. I managed to complete all the tasks I set out to do.",
            date: Date()
        )
    }
    .padding()
    .preferredColorScheme(.dark)
    .useTheme()
    .useTypography()
}
