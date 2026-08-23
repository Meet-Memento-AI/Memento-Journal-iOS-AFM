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

    /// Same interior tint as Welcome's Get Started — darkens the frost
    /// without covering it, so the capsule stays Liquid Glass.
    private static let primaryGlassTintOpacity: Double = 0.24

    public init(
        onSummarize: @escaping () -> Void,
        isSummarizing: Bool
    ) {
        self.onSummarize = onSummarize
        self.isSummarizing = isSummarizing
    }

    public var body: some View {
        VStack(spacing: 0) {
            dragHandle

            heroIcon
                .padding(.bottom, Spacing.md)

            Text("Summarize chat as an entry")
                .font(type.h4)
                .foregroundStyle(theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Spacing.xs)

            Text("Memento will summarize your key insights and reflections, and create a journal entry.")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
                .multilineTextAlignment(.center)
                .lineSpacing(type.bodyLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Spacing.xl)

            Spacer(minLength: Spacing.lg)

            actions
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
        }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(32)
        .interactiveDismissDisabled(isSummarizing)
    }

    // MARK: - Chrome

    /// House drag handle (`ChatHistorySheet`, `ProfileSheet`). The system
    /// indicator is hidden so this one is the only affordance.
    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(theme.mutedForeground.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.lg)
    }

    /// Write glyph — the same mark as the header control and FAB that open
    /// this flow. Overlay on the sheet, not its own glass, so it does not
    /// stack frost on the system sheet material. No pulse: continuous
    /// animation under glass is expensive and the loading CTA already
    /// carries the in-progress signal.
    private var heroIcon: some View {
        Group {
            if isSummarizing {
                ProgressView()
                    .controlSize(.large)
                    .tint(theme.foreground)
            } else {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(theme.foreground)
            }
        }
        .frame(width: AppHeaderMetrics.controlSize, height: AppHeaderMetrics.controlSize)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    /// Two full-width glass capsules in one sampling region. Gap (12) is
    /// larger than container spacing (8) so they stay two buttons, not one
    /// fused slab.
    private var actions: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: Spacing.sm) {
                summarizeButton
                cancelButton
            }
        }
    }

    private var summarizeButton: some View {
        Button {
            guard !isSummarizing else { return }
            onSummarize()
        } label: {
            HStack(spacing: Spacing.xxs) {
                if isSummarizing {
                    ProgressView()
                        .tint(BaseColors.white)
                } else {
                    Image(systemName: "square.and.pencil")
                }
                Text(isSummarizing ? "Generating..." : "Summarize Chat")
                    .font(type.body1Bold)
            }
            .frame(minHeight: AppHeaderMetrics.controlSize)
            .frame(maxWidth: .infinity)
            .foregroundStyle(BaseColors.white)
            .glassEffect(
                .regular.tint(BaseColors.black.opacity(Self.primaryGlassTintOpacity)),
                in: .capsule
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PrimaryButtonPressStyle())
        .disabled(isSummarizing)
        .accessibilityLabel("Summarize Chat")
        .accessibilityHint("Double-tap to turn this conversation into a journal entry")
        .accessibilityIdentifier("chat.summary.confirm")
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Cancel")
                .font(type.body1Bold)
                .frame(minHeight: AppHeaderMetrics.controlSize)
                .frame(maxWidth: .infinity)
                .foregroundStyle(theme.foreground)
                .glassEffect(.regular, in: .capsule)
                .contentShape(Capsule())
        }
        .buttonStyle(PrimaryButtonPressStyle())
        .disabled(isSummarizing)
        .opacity(isSummarizing ? 0.5 : 1)
        .accessibilityLabel("Cancel")
        .accessibilityIdentifier("chat.summary.cancel")
    }
}

// MARK: - Previews

#Preview("Default") {
    ChatSummarySheet(
        onSummarize: { AppLogger.log("Summarize tapped") },
        isSummarizing: false
    )
    .useTheme()
    .useTypography()
}

#Preview("Loading") {
    ChatSummarySheet(
        onSummarize: { AppLogger.log("Summarize tapped") },
        isSummarizing: true
    )
    .useTheme()
    .useTypography()
}

#Preview("Dark Mode") {
    ChatSummarySheet(
        onSummarize: { AppLogger.log("Summarize tapped") },
        isSummarizing: false
    )
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
