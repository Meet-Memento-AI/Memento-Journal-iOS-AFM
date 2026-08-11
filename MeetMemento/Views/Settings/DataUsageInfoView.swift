//
//  DataUsageInfoView.swift
//  MeetMemento
//
//  Information about what data is collected and how it's used
//  Required for iOS App Store transparency
//

import SwiftUI

public struct DataUsageInfoView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Data We Collect Section
                dataCollectionSection

                // How We Use Data Section
                dataUsageSection

                // AI Features Section
                aiServicesSection

                // Data Storage Section
                dataStorageSection

                // Your Rights Section
                yourRightsSection

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Data Usage")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                IconButtonNav(
                    icon: "chevron.left",
                    iconSize: 18,
                    buttonSize: 40,
                    enableHaptic: true,
                    onTap: { dismiss() }
                )
                .accessibilityLabel("Back")
            }
        }
    }

    // MARK: - Sections

    private var dataCollectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What We Collect")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "doc.text.fill",
                    title: "Journal Entries",
                    description: "Your journal entries, including titles, content, and dates. This is the core data you create in MeetMemento."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "sparkles",
                    title: "Conversations",
                    description: "Your chats with the AI companion, which grounds its replies in your own entries and cites the ones it drew from."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "person.text.rectangle.fill",
                    title: "Personalization",
                    description: "What you tell us about yourself and your goals during setup, used only to tailor reflections to you."
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var dataUsageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("How We Use Your Data")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "iphone",
                    title: "Stored On Your Device",
                    description: "Your journal lives on your iPhone, encrypted at rest. There's no account, no server copy, and no cross-device sync."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "brain.head.profile",
                    title: "Ground the AI Companion",
                    description: "When you chat, relevant entries are retrieved on your iPhone and used as context, so answers come from what you actually wrote."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "lock.shield.fill",
                    title: "Your PIN Guards Access",
                    description: "Entries are encrypted with a key stored in your device's Keychain; your PIN or Face ID unlocks the app. Neither is uploaded, and there's no account to reset through — this device is the only way in."
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var aiServicesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("AI Features")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "iphone.gen3",
                    title: "On-Device Processing",
                    description: "Speech-to-text, search, retrieval, and the AI companion all run on your iPhone using Apple's on-device models. No third-party AI service is used, and nothing you write is used to train any model."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "gearshape",
                    title: "Your Control",
                    description: "You can turn the AI companion off entirely in Settings and use Memento as a plain journal. Speech recognition is set to on-device only."
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var dataStorageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Data Storage")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "lock.shield.fill",
                    title: "Encrypted at Rest",
                    description: "Your journal is encrypted on your device with a key held in the device Keychain. There is no server copy anywhere."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "eye.slash.fill",
                    title: "Nothing Collected",
                    description: "We don't operate accounts, analytics, or servers for your journal — so there is nothing for us to share, sell, or use for advertising."
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var yourRightsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Your Rights")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "trash.fill",
                    title: "Delete Everything",
                    description: "You can permanently delete your journal and all associated data at any time from Settings > Your Data."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "questionmark.circle.fill",
                    title: "Contact Us",
                    description: "For any privacy questions or data requests, contact \(Constants.Legal.supportEmail)"
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    // MARK: - Glass Card Background

    @ViewBuilder
    private var sectionCardBackground: some View {
        // Liquid Glass removed — flat themed surface (no shadow) — cardBackground adapts to dark mode.
        RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
            .fill(theme.cardBackground)
    }
}

// MARK: - Data Item Component

private struct DataItem: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20)) // icon-size: not user text
                .foregroundStyle(theme.primary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(type.body1Medium)
                    .foregroundStyle(theme.foreground)

                Text(description)
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Previews

#Preview("Light") {
    NavigationStack {
        DataUsageInfoView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        DataUsageInfoView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.dark)
}
