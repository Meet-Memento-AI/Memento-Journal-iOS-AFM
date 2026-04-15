//
//  ChatSummarySheet.swift
//  MeetMemento
//
//  Bottom sheet modal for summarizing a chat conversation into a journal entry.
//

import SwiftUI

public struct ChatSummarySheet: View {
    let onSummarize: () -> Void
    let isSummarizing: Bool

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss

    @State private var iconPulse = false

    public init(
        onSummarize: @escaping () -> Void,
        isSummarizing: Bool
    ) {
        self.onSummarize = onSummarize
        self.isSummarizing = isSummarizing
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(theme.mutedForeground.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.lg)

            // Icon with pulse animation
            AISparkleIcon(size: 48)
                .scaleEffect(isSummarizing ? 1.1 : (iconPulse ? 1.05 : 1.0))
                .animation(
                    .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                    value: iconPulse
                )
                .padding(.bottom, Spacing.md)
                .onAppear { iconPulse = true }

            // Title
            Text("Summarize chat as an entry")
                .font(type.h4)
                .foregroundStyle(theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Spacing.xs)

            // Description
            Text("Memento will summarize your key insights and reflections, and create a journal entry.")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(type.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.xl)

            Spacer(minLength: Spacing.lg)

            // Buttons - 32px from bottom
            VStack(spacing: Spacing.sm) {
                PrimaryButton(
                    title: isSummarizing ? "Generating..." : "Summarize Chat",
                    isLoading: isSummarizing,
                    action: onSummarize
                )

                SecondaryButton(title: "Cancel") {
                    dismiss()
                }
                .disabled(isSummarizing)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .presentationBackground(theme.popover)
        .interactiveDismissDisabled(isSummarizing)
    }
}

// MARK: - Previews

#Preview("Default") {
    ChatSummarySheet(
        onSummarize: { print("Summarize tapped") },
        isSummarizing: false
    )
    .useTheme()
    .useTypography()
}

#Preview("Loading") {
    ChatSummarySheet(
        onSummarize: { print("Summarize tapped") },
        isSummarizing: true
    )
    .useTheme()
    .useTypography()
}

#Preview("Dark Mode") {
    ChatSummarySheet(
        onSummarize: { print("Summarize tapped") },
        isSummarizing: false
    )
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
