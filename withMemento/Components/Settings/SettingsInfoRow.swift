//
//  SettingsInfoRow.swift
//  MeetMemento
//
//  Non-tappable informational row used in Data Usage and similar screens.
//

import SwiftUI

struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let description: String

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(type.body1Bold)
                    .foregroundStyle(theme.foreground)

                Text(description)
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

#Preview {
    VStack(spacing: 0) {
        SettingsInfoRow(
            icon: "doc.text.fill",
            title: "Journal Entries",
            description: "Your journal entries, including titles, content, and dates."
        )
        SettingsRowDivider()
        SettingsInfoRow(
            icon: "sparkles",
            title: "Conversations",
            description: "Your chats with the AI companion."
        )
    }
    .useTheme()
    .useTypography()
}
