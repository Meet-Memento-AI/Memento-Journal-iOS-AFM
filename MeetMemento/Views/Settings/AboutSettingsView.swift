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
    @Environment(\.theme) private var theme

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
                appInfoSection
                supportSection
                legalSection
                socialSection

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
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
        SettingsSection(title: "App Information") {
            SettingsRow(
                icon: "info.circle.fill",
                title: "Version",
                subtitle: appVersion,
                showChevron: false,
                action: { copyVersionToClipboard() }
            )

            SettingsRowDivider()

            SettingsRow(
                icon: "iphone",
                title: "Device",
                subtitle: deviceInfo,
                showChevron: false,
                action: nil
            )
        }
    }

    private var supportSection: some View {
        SettingsSection(title: "Support") {
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
    }

    private var legalSection: some View {
        SettingsSection(title: "Legal") {
            SettingsRow(
                icon: "doc.text.fill",
                title: "Terms of Service",
                subtitle: nil,
                showChevron: true,
                action: {
                    openURL(Constants.Legal.termsOfServiceURL.absoluteString)
                }
            )

            SettingsRowDivider()

            SettingsRow(
                icon: "hand.raised.fill",
                title: "Privacy Policy",
                subtitle: nil,
                showChevron: true,
                action: {
                    UIApplication.shared.open(Constants.Legal.privacyPolicyURL)
                }
            )
        }
    }

    private var socialSection: some View {
        SettingsSection(title: "Share MeetMemento") {
            SettingsRow(
                icon: "star.fill",
                title: "Rate on App Store",
                subtitle: "Share your experience",
                showChevron: false,
                action: {
                    requestReview()
                }
            )

            SettingsRowDivider()

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
    }

    // MARK: - Actions

    private func copyVersionToClipboard() {
        UIPasteboard.general.string = appVersion
        showCopiedAlert = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func openContactSupport() {
        let email = Constants.Legal.supportEmail
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

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
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
