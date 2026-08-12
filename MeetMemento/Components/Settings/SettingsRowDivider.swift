//
//  SettingsRowDivider.swift
//  MeetMemento
//
//  Divider used between rows inside a Settings card.
//

import SwiftUI

struct SettingsRowDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Divider()
            .background(theme.border)
            .padding(.horizontal, Spacing.md)
    }
}

#Preview {
    VStack(spacing: 0) {
        SettingsRow(icon: "person.circle.fill", title: "Profile", showChevron: true, action: nil)
        SettingsRowDivider()
        SettingsRow(icon: "lock.fill", title: "Security", showChevron: true, action: nil)
    }
    .useTheme()
    .useTypography()
}
