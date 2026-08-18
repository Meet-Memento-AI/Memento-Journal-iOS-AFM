//
//  InlineCitationBadge.swift
//  MeetMemento
//
//  Numbered badge for inline citations in bottom sheet
//

import SwiftUI

/// Small numbered badge displaying the citation reference number
struct InlineCitationBadge: View {
    let ref: Int

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        Text("\(ref)")
            .font(type.microBold)
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(BrandColors.brandOnText)
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

// MARK: - Pill Badge Variant

/// Pill-shaped badge with 16px radius for timeline and modal headers
struct InlineCitationPillBadge: View {
    let ref: Int

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        Text("\(ref)")
            .font(type.microBold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: theme.radius.button) // 16px
                    .fill(BrandColors.brandOnText)
            )
    }
}

// MARK: - Date Badge (Inline Tappable)

/// Capsule-shaped date badge for inline citations (e.g., "Mar 5")
/// Tappable to show citation popover
struct InlineCitationDateBadge: View {
    let date: Date
    let onTap: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        Button(action: onTap) {
            Text(formattedDate)
                .font(type.captionMedium)
                .foregroundStyle(BrandColors.brandOnText)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(theme.accent.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Citation from \(formattedDate)")
        .accessibilityHint("Double-tap to view the journal excerpt")
    }
}

// MARK: - Theme Tag for inline citation theme label

/// Small tag/chip displaying the citation theme label
struct InlineCitationThemeTag: View {
    let theme: String

    @Environment(\.theme) private var themeEnv
    @Environment(\.typography) private var type

    var body: some View {
        Text(theme)
            .font(type.micro)
            .foregroundStyle(themeEnv.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(themeEnv.primary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Previews

#Preview("Inline Citation Badge") {
    HStack(spacing: 12) {
        InlineCitationBadge(ref: 1)
        InlineCitationBadge(ref: 2)
        InlineCitationBadge(ref: 3)
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Inline Citation Pill Badge") {
    HStack(spacing: 12) {
        InlineCitationPillBadge(ref: 1)
        InlineCitationPillBadge(ref: 2)
        InlineCitationPillBadge(ref: 3)
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Inline Citation Theme Tag") {
    HStack(spacing: 12) {
        InlineCitationThemeTag(theme: "work stress")
        InlineCitationThemeTag(theme: "self-care")
        InlineCitationThemeTag(theme: "relationships")
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Inline Citation Date Badge") {
    VStack(spacing: 12) {
        HStack(spacing: 8) {
            Text("You mentioned feeling stressed")
            InlineCitationDateBadge(date: Date()) {
                AppLogger.log("Tapped citation")
            }
            Text("about work.")
        }

        HStack(spacing: 8) {
            Text("Earlier you wrote about")
            InlineCitationDateBadge(
                date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!
            ) {
                AppLogger.log("Tapped citation 2")
            }
            Text("taking a walk.")
        }
    }
    .padding()
    .useTheme()
    .useTypography()
}
