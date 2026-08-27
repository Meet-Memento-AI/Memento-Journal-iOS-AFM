//
//  AISuggestionCard.swift
//  MeetMemento
//
//  Chat empty-state starter. Figma 395:5565 — theme pill and arrow on one
//  row, prompt below. Height hugs content. Colors follow the current build.
//

import SwiftUI

/// A tappable card that displays an AI prompt suggestion.
public struct AISuggestionCard: View {
    let suggestion: String
    /// Confirmed ThemeCatalog display name. Hidden when the user has no themes.
    var themeName: String? = nil
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    public init(suggestion: String, themeName: String? = nil, onTap: (() -> Void)? = nil) {
        self.suggestion = suggestion
        self.themeName = themeName
        self.onTap = onTap
    }

    init(_ suggestion: ChatSuggestion, onTap: (() -> Void)? = nil) {
        self.init(suggestion: suggestion.prompt, themeName: suggestion.themeName, onTap: onTap)
    }

    public var body: some View {
        Button(action: handleTap) {
            cardContent
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .modifier(AISuggestionCardAccessibility(label: cardAccessibilityLabel))
    }

    private func handleTap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onTap?()
    }

    /// Padding, gradient, and clip live here so `body` stays a short chain.
    /// A long single expression in this file previously blew the preview
    /// type-checker's budget (same pattern as `JournalCard`).
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            headerRow
            promptText
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
    }

    /// Figma 395:5566 — pill leading, arrow trailing, vertically centered.
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 0) {
            if let themeName, !themeName.isEmpty {
                themePill(themeName)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(chromeInk)
                .frame(width: 24, height: 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var promptText: some View {
        Text(suggestion)
            .font(type.promptTitle)
            .foregroundStyle(theme.foreground)
            .multilineTextAlignment(.leading)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func themePill(_ name: String) -> some View {
        Text(name)
            .font(type.body2Medium)
            .foregroundStyle(pillForeground)
            .lineLimit(1)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(Capsule().fill(pillFill))
    }

    /// Same copper family as the card: `primary100` on the `primary50` top
    /// of the gradient. Dark uses a lifted step of the dark card surface.
    private var pillFill: Color {
        colorScheme == .dark ? theme.journalCardChipBackground : PrimaryScale.primary100
    }

    private var pillForeground: Color {
        colorScheme == .dark ? theme.journalCardChipForeground : PrimaryScale.primary700
    }

    private var cardAccessibilityLabel: String {
        if let themeName, !themeName.isEmpty {
            return "\(themeName). \(suggestion)"
        }
        return suggestion
    }

    private var cardGradient: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [theme.journalCardGradientStart, theme.journalCardGradientEnd]
            : [PrimaryScale.primary50, PrimaryScale.primary100]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var chromeInk: Color {
        colorScheme == .dark ? theme.journalCardChipForeground : GrayScale.gray800
    }
}

// MARK: - Accessibility (split out of `body` for type-checker performance)

private struct AISuggestionCardAccessibility: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint("Sends this suggestion to AI")
    }
}

// MARK: - Previews

private struct AISuggestionCardHarness: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            AISuggestionCard(
                suggestion: "What patterns do you see in my recent entries?",
                themeName: "Mindfulness",
                onTap: { }
            )
            AISuggestionCard(
                suggestion: "How has my mood shifted over the past two weeks?",
                themeName: "Sleep",
                onTap: { }
            )
            AISuggestionCard(
                suggestion: "Summarize the key themes and emotions from my journal entries this month",
                themeName: "Goals",
                onTap: { }
            )
        }
        .padding(.horizontal, Spacing.md)
    }
}

#Preview("AISuggestionCard") {
    ScrollView {
        AISuggestionCardHarness()
    }
    .useTheme()
    .useTypography()
}

#Preview("AISuggestionCard • Long") {
    AISuggestionCard(
        suggestion: "Summarize the key themes and emotions from my journal entries this month",
        themeName: "Self-Esteem",
        onTap: { }
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("AISuggestionCard • Dark") {
    ScrollView {
        AISuggestionCardHarness()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
