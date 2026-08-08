//
//  SettingsView.swift
//  MeetMemento
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var entryViewModel: EntryViewModel
    @EnvironmentObject var appState: AppStateStore

    @State private var showDataUsageInfo = false
    @State private var showDeleteEverythingConfirmation = false
    @State private var showDeleteEverythingFinalConfirmation = false
    @State private var isDeletingEverything = false
    @State private var deleteEverythingError = ""

    @ObservedObject private var preferences = PreferencesService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Appearance Section
                appearanceSection

                // About Section
                aboutSection

                // Your Data Section (spec 023 R4 — merges the old Data & Privacy
                // and Account sections into one local-only story)
                yourDataSection

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
            "Delete everything?",
            isPresented: $showDeleteEverythingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Continue", role: .destructive) {
                showDeleteEverythingFinalConfirmation = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete every journal entry, your name, and your app-lock settings from this device. This action cannot be undone.")
        }
        .alert("Are you absolutely sure?", isPresented: $showDeleteEverythingFinalConfirmation) {
            Button("Delete Everything", role: .destructive) {
                deleteEverything()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All your data will be permanently deleted from this device. This cannot be recovered.")
        }
        .alert("Error", isPresented: .constant(!deleteEverythingError.isEmpty)) {
            Button("OK") {
                deleteEverythingError = ""
            }
        } message: {
            Text(deleteEverythingError)
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

    /// "Your Data" (spec 023 R4): one section for the whole local-only story —
    /// profile, AI on-device/PCC toggle, privacy policy, data-usage explainer,
    /// and Delete Everything. No accounts, so no Sign Out.
    private var yourDataSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Section header
            Text("Your Data")
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

                // AI Features Toggle
                HStack {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "brain")
                            .font(.system(size: 20)) // icon-size: not user text
                            .foregroundStyle(theme.primary)
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Features")
                                .font(type.body1Medium)
                                .foregroundStyle(theme.foreground)

                            Text(preferences.aiEnabled
                                ? "On-device, or Apple Private Cloud Compute for deeper reflections"
                                : "AI disabled – data stays on device")
                                .font(type.body2)
                                .foregroundStyle(theme.mutedForeground)
                        }
                    }

                    Spacer()

                    Toggle("", isOn: $preferences.aiEnabled)
                        .labelsHidden()
                        .tint(theme.primary)
                        .accessibilityLabel("AI Features")
                        .accessibilityHint(preferences.aiEnabled
                            ? "Uses on-device or Apple Private Cloud Compute AI. Double-tap to disable."
                            : "AI disabled, your data stays on device. Double-tap to enable.")
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

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                SettingsRow(
                    icon: "trash.fill",
                    title: "Delete Everything",
                    subtitle: "Permanently delete all your data from this device",
                    isDestructive: true,
                    showProgress: isDeletingEverything,
                    accessibilityIdentifier: "settings.deleteEverything",
                    action: {
                        showDeleteEverythingConfirmation = true
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
            .fill(Color(hex: "#FAFAFA"))
    }

    // MARK: - Actions

    /// Interim scope (spec 023 R4): local entry storage + security/encryption
    /// Keychain entries + UserDefaults + caches. Spec 015 extends this to the
    /// full five-store deletion per REQ-DATA-013.
    private func deleteEverything() {
        isDeletingEverything = true
        deleteEverythingError = ""
        appState.deleteEverything()
        entryViewModel.clearSessionPIN()
        isDeletingEverything = false
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
            .environmentObject(AppStateStore())
            .useTheme()
            .useTypography()
    }
}
