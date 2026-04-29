//
//  BaseTagStyle.swift
//  MeetMemento
//
//  Base styling for tag components - provides consistent pill/capsule styling
//  with configurable colors, padding, and shape variants.
//

import SwiftUI

// MARK: - Tag Style Configuration

/// Configuration for tag appearance
struct TagStyleConfig {
    var backgroundColor: Color
    var foregroundColor: Color
    var font: Font
    var verticalPadding: CGFloat = 6
    var horizontalPadding: CGFloat = 12
    var cornerRadius: CGFloat? = nil  // nil = capsule, value = rounded rectangle
    var iconSpacing: CGFloat = 8
}

// MARK: - Tag Style View Modifier

/// A reusable view modifier for consistent tag styling
struct TagStyleModifier: ViewModifier {
    let config: TagStyleConfig

    func body(content: Content) -> some View {
        content
            .font(config.font)
            .foregroundStyle(config.foregroundColor)
            .padding(.vertical, config.verticalPadding)
            .padding(.horizontal, config.horizontalPadding)
            .background(tagBackground)
    }

    @ViewBuilder
    private var tagBackground: some View {
        if let radius = config.cornerRadius {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(config.backgroundColor)
        } else {
            Capsule()
                .fill(config.backgroundColor)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Apply consistent tag styling
    func tagStyle(_ config: TagStyleConfig) -> some View {
        modifier(TagStyleModifier(config: config))
    }

    /// Apply pill-style tag (capsule background)
    func pillTagStyle(
        backgroundColor: Color,
        foregroundColor: Color = .white,
        font: Font = .system(size: 13, weight: .semibold),
        verticalPadding: CGFloat = 6,
        horizontalPadding: CGFloat = 12
    ) -> some View {
        tagStyle(TagStyleConfig(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            font: font,
            verticalPadding: verticalPadding,
            horizontalPadding: horizontalPadding,
            cornerRadius: nil
        ))
    }

    /// Apply chip-style tag (rounded rectangle background)
    func chipTagStyle(
        backgroundColor: Color,
        foregroundColor: Color,
        font: Font = .system(size: 14, weight: .semibold),
        verticalPadding: CGFloat = 10,
        horizontalPadding: CGFloat = 16,
        cornerRadius: CGFloat = 8
    ) -> some View {
        tagStyle(TagStyleConfig(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            font: font,
            verticalPadding: verticalPadding,
            horizontalPadding: horizontalPadding,
            cornerRadius: cornerRadius
        ))
    }
}

// MARK: - Preset Configurations

extension TagStyleConfig {
    /// Purple pill tag for insights (white text on purple background)
    static func insightsPill(typography: Typography) -> TagStyleConfig {
        TagStyleConfig(
            backgroundColor: PrimaryScale.primary500,
            foregroundColor: PrimaryScale.primary50,
            font: typography.captionMedium
        )
    }

    /// Dark purple pill tag for entries count
    static func entriesPill(typography: Typography) -> TagStyleConfig {
        TagStyleConfig(
            backgroundColor: PrimaryScale.primary600,
            foregroundColor: .white,
            font: typography.captionBold
        )
    }

    /// Gray chip tag for themes - uses semantic muted color for light/dark support
    static func themeChip(typography: Typography, theme: Theme) -> TagStyleConfig {
        TagStyleConfig(
            backgroundColor: theme.muted, // Use semantic token for proper light/dark support
            foregroundColor: theme.foreground,
            font: typography.body1Bold,
            verticalPadding: 10,
            horizontalPadding: 16,
            cornerRadius: 8
        )
    }
}

// MARK: - Preview

#Preview("Tag Styles") {
    VStack(spacing: 16) {
        // Pill style
        HStack(spacing: 8) {
            Image(systemName: "calendar")
            Text("Jan 15")
        }
        .pillTagStyle(
            backgroundColor: PrimaryScale.primary500,
            foregroundColor: .white
        )

        // Chip style
        Text("Work Stress")
            .chipTagStyle(
                backgroundColor: GrayScale.gray200,
                foregroundColor: GrayScale.gray900
            )
    }
    .padding()
    .background(PrimaryScale.primary900)
}
