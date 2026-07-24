import SwiftUI
import UIKit

/// A card component for displaying monthly insights with entry count and summary.
/// Features a purple gradient background with white text and navigation affordance.
public struct MonthlyInsightCard: View {
    // MARK: - Inputs
    let month: String // e.g., "January 2026"
    let summary: String // One-sentence insight summary
    let entryCount: Int

    /// Optional tap action for navigation
    var onTap: (() -> Void)? = nil

    // MARK: - Environment
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // MARK: - Initializer
    public init(month: String, summary: String, entryCount: Int, onTap: (() -> Void)? = nil) {
        self.month = month
        self.summary = summary
        self.entryCount = entryCount
        self.onTap = onTap
    }

    // MARK: - State
    @State private var isPressed = false

    // MARK: - Body
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with month and chevron
                HStack {
                    Text(month)
                        .font(type.h5)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.overlayText)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold)) // icon-size: not user text
                        .foregroundStyle(theme.overlayTextSecondary)
                }

                // Summary text
                Text(summary)
                    .font(type.body1)
                    .foregroundStyle(theme.overlayTextSecondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Entry count badge
                entryCountBadge
            }
            .vPadding(Spacing.md)
            .hPadding(Spacing.md)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            PrimaryScale.primary700.opacity(0.9),
                            PrimaryScale.primary800.opacity(Spacing.Opacity.muted)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            theme.glassBorder,
                            theme.glassBorder.opacity(0.25)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(Spacing.Opacity.border), radius: 12, x: 0, y: 6)
        .pressEffect(isPressed: $isPressed, scale: 0.98, duration: Spacing.Duration.standard)
        .contentShape(Rectangle())
        .onTapGesture {
            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onTap?()
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = pressing
            }
        }, perform: {})
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to view monthly insights")
    }

    // MARK: - Subviews

    private var entryCountBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold)) // icon-size: not user text
                .foregroundStyle(theme.overlayText)

            Text("\(entryCount) \(entryCount == 1 ? "entry" : "entries")")
                .font(type.body2Medium)
                .foregroundStyle(theme.overlayText)
        }
        .hPadding(Spacing.sm)
        .vPadding(Spacing.xs)
        .background(
            Capsule()
                .fill(theme.glassBorder)
        )
        .overlay(
            Capsule()
                .stroke(theme.glassBorder, lineWidth: 1)
        )
    }

    private var accessibilityLabel: String {
        "\(month), \(summary). \(entryCount) \(entryCount == 1 ? "entry" : "entries")"
    }
}

// MARK: - Sample Data
extension MonthlyInsightCard {
    static let sampleMonth = "January 2026"
    static let sampleSummary = "Your emotional landscape reveals a blend of reflection, frustration, and growth that you're working towards during this difficult transition."
    static let sampleEntryCount = 5
}

// MARK: - Preview Harness
private struct MonthlyInsightCardHarness: View {
    var body: some View {
        VStack(spacing: 20) {
            MonthlyInsightCard(
                month: MonthlyInsightCard.sampleMonth,
                summary: MonthlyInsightCard.sampleSummary,
                entryCount: MonthlyInsightCard.sampleEntryCount,
                onTap: { /* no-op */ }
            )

            MonthlyInsightCard(
                month: "February 2026",
                summary: "Add a one sentence summary of the users insights this month.",
                entryCount: 11,
                onTap: { /* no-op */ }
            )

            MonthlyInsightCard(
                month: "March 2026",
                summary: "Add a one sentence summary of the users insights this month.",
                entryCount: 11,
                onTap: { /* no-op */ }
            )
        }
        .padding()
        .background(theme.insightsBackground.ignoresSafeArea())
        .useTheme()
        .useTypography()
    }

    @Environment(\.theme) private var theme
}

#Preview("MonthlyInsightCard · Light") {
    MonthlyInsightCardHarness()
        .preferredColorScheme(.light)
}

#Preview("MonthlyInsightCard · Dark") {
    MonthlyInsightCardHarness()
        .preferredColorScheme(.dark)
}

#Preview("MonthlyInsightCard · Single Entry") {
    MonthlyInsightCard(
        month: "December 2025",
        summary: "A month of reflection and new beginnings.",
        entryCount: 1
    )
    .padding()
    .background(PrimaryScale.primary900)
    .useTheme()
    .useTypography()
}
