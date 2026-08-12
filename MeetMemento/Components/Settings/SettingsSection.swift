//
//  SettingsSection.swift
//  MeetMemento
//
//  Shared Settings section: h5 title, optional subtitle, and card chrome.
//
//  Settings type scale (by weight):
//  - Bold: section titles (h5), row titles (body1Bold), primary actions (body1Bold)
//  - Medium: secondary copy — section subtitles, row subtitles, explainers (body2)
//

import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(title)
                    .font(type.h5)
                    .foregroundStyle(theme.foreground)
                    .padding(.bottom, subtitle == nil ? Spacing.xxs : 0)

                if let subtitle {
                    Text(subtitle)
                        .font(type.body2)
                        .foregroundStyle(theme.mutedForeground)
                }
            }

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                    .fill(theme.cardBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }
}

#Preview {
    SettingsSection(title: "Appearance", subtitle: "Choose light, dark, or system") {
        SettingsRow(
            icon: "paintbrush.fill",
            title: "Theme & Display",
            subtitle: "Customize appearance",
            showChevron: true,
            action: nil
        )
    }
    .padding()
    .useTheme()
    .useTypography()
}
