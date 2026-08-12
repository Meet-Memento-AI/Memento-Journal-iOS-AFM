//
//  SettingsToggleRow.swift
//  MeetMemento
//
//  Settings row with a trailing Toggle.
//

import SwiftUI

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var accessibilityIdentifier: String? = nil
    var accessibilityHint: String? = nil

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        HStack {
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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.primary)
                .accessibilityLabel(title)
                .accessibilityHint(accessibilityHint ?? "")
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

private struct SettingsToggleRowPreview: View {
    @State private var enabled = true
    var body: some View {
        SettingsToggleRow(
            icon: "brain",
            title: "AI Features",
            subtitle: "Generated on-device with Apple Intelligence",
            isOn: $enabled,
            accessibilityIdentifier: "settings.ai"
        )
        .useTheme()
        .useTypography()
    }
}

#Preview {
    SettingsToggleRowPreview()
}
