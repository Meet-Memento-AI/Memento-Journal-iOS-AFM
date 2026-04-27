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
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Spacer(minLength: Spacing.md)

                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Data Collection")
                        .font(type.h3)
                        .headerGradient()

                    Text("What we collect and why")
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)

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
            }
        }
    }

    // MARK: - Sections

    private var dataCollectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What We Collect")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, Spacing.md)
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
                    icon: "person.circle.fill",
                    title: "Account Information",
                    description: "Your email address and authentication tokens to secure your account and data."
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .padding(.horizontal, Spacing.md)
        }
    }

    private var dataUsageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("How We Use Your Data")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "cloud.fill",
                    title: "Sync Across Devices",
                    description: "Your data is stored securely in the cloud so you can access your journal from any device."
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
                    icon: "shield.fill",
                    title: "Account Security",
                    description: "Your email and authentication data are used solely to secure your account and prevent unauthorized access."
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .padding(.horizontal, Spacing.md)
        }
    }

    private var aiServicesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("AI Features")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "brain",
                    title: "AI-Powered Features",
                    description: "Chat and Insights use Google Gemini. Your journal content is sent securely to generate responses. Google doesn't train on your data."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "arrow.up.doc",
                    title: "What's Processed",
                    description: "AI Chat: Your message + relevant entries. Insights: Selected entries (up to 500 chars each)."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "gearshape",
                    title: "Your Control",
                    description: "You can disable AI features anytime in Settings > Data & Privacy. When disabled, no data is sent to AI services."
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .padding(.horizontal, Spacing.md)
        }
    }

    private var dataStorageSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Data Storage")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "lock.shield.fill",
                    title: "Encrypted in Transit",
                    description: "All data is transmitted securely using HTTPS encryption. Your device PIN protects local access."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "server.rack",
                    title: "Secure Cloud Storage",
                    description: "Your data is stored on secure Supabase servers with robust backup and disaster recovery systems."
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
            .padding(.horizontal, Spacing.md)
        }
    }

    private var yourRightsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Your Rights")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xxs)

            VStack(alignment: .leading, spacing: Spacing.md) {
                DataItem(
                    icon: "trash.fill",
                    title: "Delete Your Account",
                    description: "You can permanently delete your account and all associated data at any time from Settings."
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                DataItem(
                    icon: "questionmark.circle.fill",
                    title: "Contact Us",
                    description: "For any privacy questions or data requests, contact support@sebastianmendo.com"
                )
            }
            .padding(.vertical, Spacing.sm)
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Glass Card Background

    @ViewBuilder
    private var sectionCardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .mementoGlassEffect(.regular, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        } else {
            colorScheme == .dark ? GrayScale.gray800 : GrayScale.gray100
        }
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
                .font(.system(size: 20))
                .foregroundStyle(theme.primary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.foreground)

                Text(description)
                    .font(.system(size: 14))
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
