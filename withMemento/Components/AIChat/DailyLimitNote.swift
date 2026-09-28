//
//  DailyLimitNote.swift
//  withMemento
//
//  Spec 021 R4/R9 moment 2: shown above the composer when the free chat's
//  daily message limit holds a message back. Memento's own limit — it never
//  mentions Apple, iCloud+ or quota, and never shows a running count
//  (017 R3 amendment). The Upgrade button opens the paywall
//  (`PaywallTrigger.dailyLimit`, placement `daily_limit`).
//

import SwiftUI

struct DailyLimitNote: View {
    let onUpgrade: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            Text("More to say? Your free messages return tomorrow.")
                .font(type.body2)
                .foregroundStyle(theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onUpgrade) {
                Text("Upgrade")
                    .font(type.pillLabel)
                    .foregroundStyle(colorScheme == .dark ? PrimaryScale.primary300 : PrimaryScale.primary650)
                    .fixedSize()
                    .frame(minHeight: 44) // AX5: minHeight
                    .padding(.horizontal, Spacing.xs)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Upgrade to Memento Pro")
            .accessibilityIdentifier("chat.dailyLimit.upgrade")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.dailyLimit")
    }
}

#Preview {
    DailyLimitNote {}
        .padding()
        .useTheme()
        .useTypography()
}
