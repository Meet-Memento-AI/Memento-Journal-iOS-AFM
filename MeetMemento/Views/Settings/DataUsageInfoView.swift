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
                    title: "Insights",
                    description: "AI-generated insights based on your journal entries to help you reflect on patterns and growth."
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
                    description: "Your journal lives on your iPhone, encrypted with your PIN. There's no account and nothing is uploaded to sync it across devices."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "brain.head.profile",
                    title: "Generate Insights",
                    description: "We use AI to analyze your entries and provide personalized insights about your patterns and growth."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "lock.shield.fill",
                    title: "Your PIN Protects Everything",
                    description: "Your PIN is the only key to your encrypted journal. It's never sent anywhere, and there's no account to reset it through — losing it means losing access unless you use device passcode fallback."
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
                    title: "On-Device First",
                    description: "Transcription, tagging, mood, search, and single-entry reflections run entirely on your iPhone. These work in airplane mode."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "apple.logo",
                    title: "Private Cloud Compute for Deeper Reflections",
                    description: "Weekly and monthly reflections may use Apple's Private Cloud Compute, which stores nothing and is independently verifiable. No third-party AI is ever used, and nothing you write is used to train any model."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "gearshape",
                    title: "Your Control",
                    description: "You can pin everything to on-device processing anytime in Settings > Your Data."
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
                    description: "Your journal is encrypted on your device using a key derived from your PIN. It's unreadable without it, even to us."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "eye.slash.fill",
                    title: "Private by Default",
                    description: "Your journal entries are completely private. We never share, sell, or use your personal data for advertising."
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
                    description: "For any privacy questions or data requests, contact \(Constants.Support.email)"
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
        // Liquid Glass removed — flat #fafafa surface (no shadow).
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
