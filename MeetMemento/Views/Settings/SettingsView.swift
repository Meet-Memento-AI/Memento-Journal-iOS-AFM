//
//  SettingsView.swift
//  MeetMemento
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var entryViewModel: EntryViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var showDataUsageInfo = false
    @State private var showSignOutConfirmation = false
    @State private var isSigningOut = false
    @State private var showDeleteAccountConfirmation = false
    @State private var showDeleteAccountFinalConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError = ""

    @ObservedObject private var preferences = PreferencesService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Appearance Section
                appearanceSection

                // About Section
                aboutSection

                // Data & Privacy Section
                dataPrivacySection

                // Account Section
                accountSection

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showDataUsageInfo) {
            NavigationStack {
                DataUsageInfoView()
                    .useTheme()
                    .useTypography()
            }
        }
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                signOut()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .confirmationDialog(
            "Delete Account?",
            isPresented: $showDeleteAccountConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                showDeleteAccountFinalConfirmation = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all your journal entries. This action cannot be undone.")
        }
        .alert("Are you absolutely sure?", isPresented: $showDeleteAccountFinalConfirmation) {
            Button("Delete My Account", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All your data will be permanently deleted. This cannot be recovered.")
        }
        .alert("Error", isPresented: .constant(!deleteAccountError.isEmpty)) {
            Button("OK") {
                deleteAccountError = ""
            }
        } message: {
            Text(deleteAccountError)
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            Text("Appearance")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            // Section content card
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.appearance) {
                    SettingsRow(
                        icon: "paintbrush.fill",
                        title: "Theme & Display",
                        subtitle: "Customize colors and text size",
                        showChevron: true,
                        action: nil
                    )
                }
                .buttonStyle(.plain)
            }
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            Text("About")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            // Section content card
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.about) {
                    SettingsRow(
                        icon: "info.circle.fill",
                        title: "About MeetMemento",
                        subtitle: "Version, legal, and support",
                        showChevron: true,
                        action: nil
                    )
                }
                .buttonStyle(.plain)
            }
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var dataPrivacySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            Text("Data & Privacy")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            // Section content card
            VStack(spacing: 0) {
                // AI Features Toggle
                HStack {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "brain")
                            .font(.system(size: 20))
                            .foregroundStyle(theme.primary)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Features")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(theme.foreground)

                            Text(preferences.aiEnabled
                                ? "Chat and Insights use cloud AI"
                                : "AI disabled – data stays on device")
                                .font(.system(size: 14))
                                .foregroundStyle(theme.mutedForeground)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $preferences.aiEnabled)
                        .labelsHidden()
                        .tint(theme.primary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                SettingsRow(
                    icon: "hand.raised",
                    title: "Privacy Policy",
                    subtitle: "How we protect your data",
                    showChevron: true,
                    action: {
                        if let url = URL(string: "https://sebmendo1.github.io/MeetMemento/privacy.html") {
                            UIApplication.shared.open(url)
                        }
                    }
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                SettingsRow(
                    icon: "info.circle",
                    title: "What Data We Collect",
                    subtitle: "Learn about data usage",
                    showChevron: true,
                    action: {
                        showDataUsageInfo = true
                    }
                )
            }
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }


    private var accountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            Text("Account")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            // Section content card
            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.profile) {
                    SettingsRow(
                        icon: "person.circle.fill",
                        title: "Profile",
                        subtitle: "Edit your name",
                        showChevron: true,
                        action: nil
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                SettingsRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Sign Out",
                    subtitle: "Sign out of your account",
                    showProgress: isSigningOut,
                    action: {
                        showSignOutConfirmation = true
                    }
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                SettingsRow(
                    icon: "trash.fill",
                    title: "Delete Account",
                    subtitle: "Permanently delete your account",
                    isDestructive: true,
                    showProgress: isDeletingAccount,
                    action: {
                        showDeleteAccountConfirmation = true
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
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .mementoGlassEffect(.regular, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        } else {
            colorScheme == .dark ? GrayScale.gray800 : GrayScale.gray100
        }
    }

    // MARK: - Actions

    private func signOut() {
        isSigningOut = true
        Task {
            await authViewModel.signOut()
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        deleteAccountError = ""
        Task {
            do {
                try await authViewModel.deleteAccount()
            } catch {
                await MainActor.run {
                    isDeletingAccount = false
                    deleteAccountError = "Failed to delete account. Please try again or contact support."
                }
            }
        }
    }
}

// MARK: - ShareSheet Helper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)

        // iPad popover configuration (required to prevent crash on iPad)
        if let popover = controller.popoverPresentationController {
            // Get the window scene to find a source view
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootView = window.rootViewController?.view {
                popover.sourceView = rootView
                popover.sourceRect = CGRect(x: rootView.bounds.midX, y: rootView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(EntryViewModel())
            .environmentObject(AuthViewModel())
            .useTheme()
            .useTypography()
    }
}
