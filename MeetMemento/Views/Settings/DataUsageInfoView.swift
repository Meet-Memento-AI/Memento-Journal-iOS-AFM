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

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                dataCollectionSection
                dataUsageSection
                aiServicesSection
                dataStorageSection
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
                    enableHaptic: true,
                    onTap: { dismiss() }
                )
                .accessibilityLabel("Back")
            }
        }
    }

    // MARK: - Sections

    private var dataCollectionSection: some View {
        SettingsSection(title: "What We Collect") {
            SettingsInfoRow(
                icon: "doc.text.fill",
                title: "Journal Entries",
                description: "Your journal entries, including titles, content, and dates. This is the core data you create in MeetMemento."
            )

            SettingsRowDivider()

            SettingsInfoRow(
                icon: "sparkles",
                title: "Conversations",
                description: "Your chats with the AI companion, which grounds its replies in your own entries and cites the ones it drew from."
            )

            SettingsRowDivider()

            SettingsInfoRow(
                icon: "person.text.rectangle.fill",
                title: "Personalization",
                description: "What you tell us about yourself and your goals during setup, used only to tailor reflections to you."
            )
        }
    }

    private var dataUsageSection: some View {
        SettingsSection(title: "How We Use Your Data") {
            SettingsInfoRow(
                icon: "iphone",
                title: "Stored On Your Device",
                description: "Your journal lives on your iPhone, encrypted at rest. There's no account, no server copy, and no cross-device sync."
            )

            SettingsRowDivider()

            SettingsInfoRow(
                icon: "brain.head.profile",
                title: "Ground the AI Companion",
                description: "When you chat, relevant entries are retrieved on your iPhone and used as context, so answers come from what you actually wrote."
            )

            SettingsRowDivider()

            SettingsInfoRow(
                icon: "lock.shield.fill",
                title: "Your PIN Guards Access",
                description: "Entries are encrypted with a key stored in your device's Keychain; your PIN or Face ID unlocks the app. Neither is uploaded, and there's no account to reset through — this device is the only way in."
            )
        }
    }

    private var aiServicesSection: some View {
        SettingsSection(title: "AI Features") {
            SettingsInfoRow(
                icon: "iphone.gen3",
                title: "On-Device Processing",
                description: "Speech-to-text, search, retrieval, and the AI companion all run on your iPhone using Apple's on-device models. No third-party AI service is used, and nothing you write is used to train any model."
            )

            SettingsRowDivider()

            SettingsInfoRow(
                icon: "gearshape",
                title: "Your Control",
                description: "You can turn the AI companion off entirely in Settings and use Memento as a plain journal. Speech recognition is set to on-device only."
            )
        }
    }

    private var dataStorageSection: some View {
        SettingsSection(title: "Data Storage") {
            SettingsInfoRow(
                icon: "lock.shield.fill",
                title: "Encrypted at Rest",
                description: "Your journal is encrypted on your device with a key held in the device Keychain. There is no server copy anywhere."
            )

            SettingsRowDivider()

            SettingsInfoRow(
                icon: "eye.slash.fill",
                title: "Nothing Collected",
                description: "We don't operate accounts, analytics, or servers for your journal — so there is nothing for us to share, sell, or use for advertising."
            )
        }
    }

    private var yourRightsSection: some View {
        SettingsSection(title: "Your Rights") {
            SettingsInfoRow(
                icon: "trash.fill",
                title: "Delete Everything",
                description: "You can permanently delete your journal and all associated data at any time from Settings > Your Data."
            )

            SettingsRowDivider()

            SettingsInfoRow(
                icon: "questionmark.circle.fill",
                title: "Contact Us",
                description: "For any privacy questions or data requests, contact \(Constants.Legal.supportEmail)"
            )
        }
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
