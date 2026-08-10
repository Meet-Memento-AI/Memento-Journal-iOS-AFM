//
//  AboutSettingsView.swift
//  MeetMemento
//
//  About page with version, legal links, and support options
//  REQUIRED for App Store submission
//

import SwiftUI
import StoreKit

public struct AboutSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var showShareSheet = false
    @State private var showCopiedAlert = false

    // App information
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (Build \(build))"
    }

    private var deviceInfo: String {
        let device = UIDevice.current.model
        let osVersion = UIDevice.current.systemVersion
        return "\(device) • iOS \(osVersion)"
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // App Info Section
                appInfoSection

                // Support Section
                supportSection

                // Legal Section
                legalSection

                // Social Section
                socialSection

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("About")
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
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: [shareMessage])
        }
        .alert("Copied!", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("App version copied to clipboard")
        }
    }

    // MARK: - Sections

    private var appInfoSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("App Information")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(spacing: 0) {
                // Version info (tappable to copy)
                Button {
                    copyVersionToClipboard()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 20)) // icon-size: not user text
                            .foregroundStyle(theme.primary)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Version")
                                .font(type.body1)
                                .foregroundStyle(theme.foreground)

                            Text(appVersion)
                                .font(type.body2)
                                .foregroundStyle(theme.mutedForeground)
                        }

                        Spacer()

                        Text("Tap to copy")
                            .font(type.caption)
                            .foregroundStyle(theme.mutedForeground)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                // Device info (read-only)
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "iphone")
                        .font(.system(size: 20)) // icon-size: not user text
                        .foregroundStyle(theme.primary)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Device")
                            .font(type.body1)
                            .foregroundStyle(theme.foreground)

                        Text(deviceInfo)
                            .font(type.body2)
                            .foregroundStyle(theme.mutedForeground)
                    }

                    Spacer()
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
            }
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Support")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(spacing: 0) {
                // Contact Support
                SettingsRow(
                    icon: "envelope.fill",
                    title: "Contact Support",
                    subtitle: "Get help with MeetMemento",
                    showChevron: false,
                    action: {
                        openContactSupport()
                    }
                )
            }
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Legal")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(spacing: 0) {
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: "Privacy Policy",
                    subtitle: nil,
                    showChevron: true,
                    action: {
                        openURL(Constants.Legal.privacyPolicyURL)
                    }
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                SettingsRow(
                    icon: "doc.text.fill",
                    title: "Terms of Service",
                    subtitle: nil,
                    showChevron: true,
                    action: {
                        openURL(Constants.Legal.termsOfServiceURL)
                    }
                )
            }
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Share MeetMemento")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(spacing: 0) {
                // Rate on App Store
                SettingsRow(
                    icon: "star.fill",
                    title: "Rate on App Store",
                    subtitle: "Share your experience",
                    showChevron: false,
                    action: {
                        requestReview()
                    }
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                // Share App
                SettingsRow(
                    icon: "square.and.arrow.up.fill",
                    title: "Share App",
                    subtitle: "Tell your friends",
                    showChevron: false,
                    action: {
                        showShareSheet = true
                    }
                )
            }
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

    // MARK: - Actions

    private func copyVersionToClipboard() {
        UIPasteboard.general.string = appVersion
        showCopiedAlert = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openContactSupport() {
        let email = Constants.Support.email
        let subject = "MeetMemento Support Request"
        let body = """


        ---
        App: MeetMemento
        Version: \(appVersion)
        Device: \(deviceInfo)
        ---
        """

        if let encoded = "mailto:\(email)?subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }

    private func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }

    private func requestReview() {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }

    private var shareMessage: String {
        "Check out MeetMemento - Your space for growth & reflection! 📝✨"
    }
}


// MARK: - Previews

#Preview("Light") {
    NavigationStack {
        AboutSettingsView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        AboutSettingsView()
            .useTheme()
            .useTypography()
    }
    .preferredColorScheme(.dark)
}
