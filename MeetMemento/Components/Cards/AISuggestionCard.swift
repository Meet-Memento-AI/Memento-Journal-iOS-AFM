//
//  AISuggestionCard.swift
//  MeetMemento
//
//  Chat empty-state starter. Figma 709:2320 — cream gradient, 18pt prompt,
//  circular arrow bottom-leading. No category tag. Tokens only.
//

import SwiftUI

/// A tappable card that displays an AI prompt suggestion with a circular arrow.
public struct AISuggestionCard: View {
    let suggestion: String
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    /// 160×200 — slightly portrait, same size for every starter in the row.
    private static let cardWidth: CGFloat = 160
    private static let cardHeight: CGFloat = 200

    public init(suggestion: String, onTap: (() -> Void)? = nil) {
        self.suggestion = suggestion
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap?()
        }) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(suggestion)
                    .font(type.promptTitle)
                    .foregroundStyle(PrimaryScale.primary600)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chromeInk)
                    .frame(width: 24, height: 24)
                    .padding(Spacing.xxs)
                    .background(Circle().fill(arrowFill))
            }
            .padding(Spacing.md)
            .frame(width: Self.cardWidth, height: Self.cardHeight, alignment: .topLeading)
            .background(cardGradient)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(suggestion)
        .accessibilityHint("Sends this suggestion to AI")
    }

    private var cardGradient: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [theme.journalCardGradientStart, theme.journalCardGradientEnd]
            : [PrimaryScale.primary50, PrimaryScale.primary100]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var arrowFill: Color {
        colorScheme == .dark ? theme.journalCardChipBackground : PrimaryScale.primary200
    }

    private var chromeInk: Color {
        colorScheme == .dark ? theme.journalCardChipForeground : GrayScale.gray800
    }
}

// MARK: - Previews

#Preview("AISuggestionCard") {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: Spacing.md) {
            AISuggestionCard(
                suggestion: "What patterns do you see in my recent entries?",
                onTap: { }
            )
            AISuggestionCard(
                suggestion: "How has my mood shifted over the past two weeks?",
                onTap: { }
            )
            AISuggestionCard(
                suggestion: "Summarize my week in one sentence and suggest one intention for next week.",
                onTap: { }
            )
        }
        .padding(.horizontal, Spacing.md)
    }
    .useTheme()
    .useTypography()
}

#Preview("AISuggestionCard • Long") {
    AISuggestionCard(
        suggestion: "Summarize the key themes and emotions from my journal entries this month",
        onTap: { }
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("AISuggestionCard • Dark") {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: Spacing.md) {
            AISuggestionCard(
                suggestion: "What patterns do you see in my recent entries?",
                onTap: { }
            )
            AISuggestionCard(
                suggestion: "How has my mood shifted over the past two weeks?",
                onTap: { }
            )
            AISuggestionCard(
                suggestion: "Summarize the key themes and emotions from my journal entries this month",
                onTap: { }
            )
        }
        .padding(.horizontal, Spacing.md)
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
