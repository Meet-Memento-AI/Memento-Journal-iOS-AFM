//
//  UpgradePill.swift
//  withMemento
//
//  Free chat header's "✦ Upgrade" (Figma 1177:3174). The same capsule glass
//  as every header control, so it sits in `AppHeader`'s one glass container
//  with the Journal button. Opens the paywall (spec 021 R9, placement
//  `locked_surface`).
//

import SwiftUI

struct UpgradePill: View {
    let action: () -> Void

    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Figma's #6F5749 on light glass; the light end of the brand ramp on
    /// dark glass, where the brown would disappear.
    private var labelColor: Color {
        colorScheme == .dark ? PrimaryScale.primary300 : PrimaryScale.primary650
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image("UpgradeSparkle")
                    .resizable()
                    .frame(width: 24, height: 24) // icon-size: not user text
                    .accessibilityHidden(true)
                Text("Upgrade")
                    .font(type.pillLabel)
                    .foregroundStyle(labelColor)
                    .fixedSize()
            }
            .padding(.horizontal, Spacing.md)
            .mementoGlassButtonChrome(interactive: !reduceMotion)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Header chrome: grows with Dynamic Type, but capped so the pill
        // can't crowd the Journal and reset buttons off the row.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityLabel("Upgrade to Memento Pro")
        .accessibilityIdentifier("chat.header.upgrade")
    }
}

#Preview {
    UpgradePill {}
        .padding()
        .useTheme()
        .useTypography()
}
