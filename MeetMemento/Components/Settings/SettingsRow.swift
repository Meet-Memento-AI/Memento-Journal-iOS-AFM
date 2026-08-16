//
//  SettingsRow.swift
//  MeetMemento
//
//  Reusable settings row component with icon, title, subtitle, and optional chevron.
//

import SwiftUI

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let showChevron: Bool
    let isDestructive: Bool
    let showProgress: Bool
    let action: (() -> Void)?
    let accessibilityIdentifier: String?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        showChevron: Bool = false,
        isDestructive: Bool = false,
        showProgress: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.showChevron = showChevron
        self.isDestructive = isDestructive
        self.showProgress = showProgress
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    var body: some View {
        // Only wrap in Button if there's an action (not when used with NavigationLink)
        if let action = action {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .disabled(showProgress)
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
        } else {
            // No button wrapper - used when wrapped in NavigationLink.
            // The identifier still applies here — without it, rows inside
            // NavigationLinks (settings.voice, settings.security) are
            // unreachable by accessibility identifier in UI tests.
            rowContent
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
    }

    private var rowContent: some View {
        HStack(spacing: Spacing.sm) {
            // Icon — fixed 20pt to match toggle/selectable/info rows
            Image(systemName: icon)
                .font(.system(size: 20)) // icon-size: not user text
                .foregroundStyle(isDestructive ? theme.destructive : theme.primary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            // Title and subtitle
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(type.body1Bold)
                    .foregroundStyle(isDestructive ? theme.destructive : theme.foreground)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(type.body2)
                        .foregroundStyle(theme.mutedForeground)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Trailing element
            if showProgress {
                ProgressView()
                    .tint(theme.primary)
            } else if showChevron {
                Image(systemName: "chevron.right")
                    .font(type.body2Bold)
                    .foregroundStyle(theme.foreground.opacity(0.3))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

#Preview("Settings Row") {
    VStack(spacing: 0) {
        SettingsRow(
            icon: "person.circle.fill",
            title: "Profile",
            subtitle: "Edit your name and info",
            showChevron: true,
            action: {}
        )

        Divider()

        SettingsRow(
            icon: "paintbrush.fill",
            title: "Appearance",
            subtitle: "Theme and display settings",
            showChevron: true,
            action: {}
        )

        Divider()

        SettingsRow(
            icon: "trash.fill",
            title: "Delete Account",
            subtitle: "Permanently delete all data",
            isDestructive: true,
            action: {}
        )
    }
    .background(Color(uiColor: .systemBackground))
    .cornerRadius(12)
    .padding()
    .useTheme()
    .useTypography()
}
