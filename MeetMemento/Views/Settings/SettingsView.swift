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
    @ObservedObject private var sampleContent = SampleContentService.shared
    @State private var isSampleWorking = false

    @State private var exportURLs: [URL] = []
    @State private var showExportSheet = false
    @State private var showNothingToExportAlert = false
    @State private var exportError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Appearance Section
                appearanceSection

                // Security Section — the app lock, changeable after onboarding.
                // Onboarding's skip dialog promises "you can turn this on later
                // in Settings"; before this section existed, it could not.
                securitySection

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
        .sheet(isPresented: $showExportSheet, onDismiss: {
            // The plaintext export exists only for the handoff.
            JournalExporter.cleanUp()
            exportURLs = []
        }) {
            ShareSheet(items: exportURLs)
        }
        .alert("Nothing to export yet", isPresented: $showNothingToExportAlert) {
            Button("OK") { }
        } message: {
            Text("Write an entry first — sample entries aren't included in exports.")
        }
        .alert("Export failed", isPresented: $exportError) {
            Button("OK") { }
        } message: {
            Text("Your export couldn't be written. Free up some space and try again.")
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

    /// The app lock, controllable after onboarding. `SecuritySettingsView`
    /// explains why this was structurally impossible until the encryption key
    /// was decoupled from the PIN.
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Security")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .padding(.bottom, Spacing.xxs)

            VStack(spacing: 0) {
                NavigationLink(value: SettingsRoute.security) {
                    SettingsRow(
                        icon: "lock.fill",
                        title: "App Lock",
                        subtitle: securitySubtitle,
                        showChevron: true,
                        accessibilityIdentifier: "settings.security",
                        action: nil
                    )
                }
                .buttonStyle(.plain)
            }
            .background(sectionCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        }
    }

    private var securitySubtitle: String {
        switch SecurityService.shared.currentMode {
        case .faceID: return "\(SecurityService.shared.biometricType ?? "Face ID") and PIN"
        case .pin: return "PIN required to open"
        case .none: return "Off — anyone with your phone can read your journal"
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
                                ? "Generated on-device with Apple Intelligence"
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
                            ? "Uses Apple's on-device AI. Double-tap to disable."
                            : "AI disabled, your data stays on device. Double-tap to enable.")
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                // Sample entries. Memento reflects on what you've written, so a
                // fresh install has nothing for Weekly, Patterns or Ask to work
                // with — a weak first impression, and a Guideline 2.1 risk since
                // a reviewer opens the app cold with an empty journal.
                SettingsRow(
                    icon: sampleContent.isLoaded ? "trash" : "text.book.closed",
                    title: sampleContent.isLoaded ? "Remove Sample Entries" : "Load Sample Entries",
                    subtitle: sampleContent.isLoaded
                        ? "Deletes only the \(sampleContent.loadedCount) sample entries — your own writing is untouched"
                        : "Adds a fictional 9-month journal so you can try reflections right away",
                    showChevron: false,
                    showProgress: isSampleWorking,
                    accessibilityIdentifier: "settings.sampleEntries",
                    action: { toggleSampleEntries() }
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                // Export. The archive is the user's — hand it over in portable
                // formats, whole, on demand. Sample entries are excluded so
                // the export is what they wrote, not the bundled fiction.
                SettingsRow(
                    icon: "square.and.arrow.up",
                    title: "Export Your Journal",
                    subtitle: "Markdown and JSON files of everything you've written",
                    showChevron: false,
                    accessibilityIdentifier: "settings.exportJournal",
                    action: { exportJournal() }
                )

                Divider()
                    .background(theme.border)
                    .padding(.horizontal, Spacing.md)

                SettingsRow(
                    icon: "hand.raised",
                    title: "Privacy Policy",
                    subtitle: "How we protect your data",
                    showChevron: true,
                    action: {
                        UIApplication.shared.open(Constants.Legal.privacyPolicyURL)
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
        // Liquid Glass removed — flat themed surface (no shadow) — cardBackground adapts to dark mode.
        RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
            .fill(theme.cardBackground)
    }

    // MARK: - Actions

    /// Interim scope (spec 023 R4): local entry storage + security/encryption
    /// Keychain entries + UserDefaults + caches. Spec 015 extends this to the
    /// full five-store deletion per REQ-DATA-013.
    /// Loads or removes the bundled sample journal. Reversible by design — it
    /// tracks the ids it created, so removal never touches the user's own
    /// entries even if a sample was edited afterwards.
    private func toggleSampleEntries() {
        guard !isSampleWorking else { return }
        isSampleWorking = true
        let wasLoaded = sampleContent.isLoaded
        Task {
            if wasLoaded {
                sampleContent.remove()
            } else {
                sampleContent.load()
            }
            await entryViewModel.loadEntries()
            isSampleWorking = false
        }
    }

    /// Writes the user's entries (sample entries excluded) as Markdown + JSON
    /// and hands them to the share sheet. Files are cleaned up on dismiss.
    private func exportJournal() {
        let ownEntries = entryViewModel.entries.filter { !sampleContent.isSampleEntry($0.id) }
        guard !ownEntries.isEmpty else {
            showNothingToExportAlert = true
            return
        }
        do {
            exportURLs = try JournalExporter.writeExportFiles(entries: ownEntries)
            showExportSheet = true
        } catch {
            AppLogger.log("⚠️ [Settings] Journal export failed: \(error.localizedDescription)")
            exportError = true
        }
    }

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
