//
//  SettingsSelectableRow.swift
//  MeetMemento
//
//  Selectable Settings row with checkmark trailing (theme picker, etc.).
//  Matches SettingsRow chrome: icon frame, title weight, padding, spacing.
//

import SwiftUI

struct SettingsSelectableRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 20)) // icon-size: not user text
                    .foregroundStyle(theme.primary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(type.body1Bold)
                        .foregroundStyle(theme.foreground)

                    Text(subtitle)
                        .font(type.body2)
                        .foregroundStyle(theme.mutedForeground)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)) // icon-size: not user text
                    .foregroundStyle(isSelected ? theme.primary : theme.foreground.opacity(0.3))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    SettingsSection(title: "Theme") {
        SettingsSelectableRow(
            icon: "sun.max.fill",
            title: "Light",
            subtitle: "Always use light mode",
            isSelected: true,
            action: {}
        )
        SettingsRowDivider()
        SettingsSelectableRow(
            icon: "moon.fill",
            title: "Dark",
            subtitle: "Always use dark mode",
            isSelected: false,
            action: {}
        )
    }
    .padding()
    .useTheme()
    .useTypography()
}
