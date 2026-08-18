//
//  SettingsView.swift
//  MeetMemento
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @Environment(\.theme) private var theme
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
                appearanceSection
                voiceSection
                securitySection
                aboutSection
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
        SettingsSection(title: "Appearance") {
            NavigationLink(value: SettingsRoute.appearance) {
                SettingsRow(
                    icon: "paintbrush.fill",
                    title: "Theme & Display",
                    subtitle: "Choose light, dark, or system appearance",
                    showChevron: true,
                    action: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Read-aloud voice + speed (spec 018 R7). A presentation preference, so
    /// it sits with Appearance rather than in Your Data's privacy narrative.
    private var voiceSection: some View {
        SettingsSection(title: "Voice") {
            NavigationLink(value: SettingsRoute.voice) {
                SettingsRow(
                    icon: "speaker.wave.2.fill",
                    title: "Read Aloud",
                    subtitle: voiceSubtitle,
                    showChevron: true,
                    accessibilityIdentifier: "settings.voice",
                    action: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Live device state, `securitySubtitle`-style: names the effective voice,
    /// and — per R7's acceptance criterion — surfaces the Enhanced-voice
    /// download whenever playback would fall back to a compact voice. Never a
    /// silent fallback.
    private var voiceSubtitle: String {
        let chosen = PreferencesService.shared.selectedVoiceIdentifier
            .flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        if let chosen {
            switch chosen.quality {
            case .premium: return "\(chosen.name) — Premium"
            case .enhanced: return "\(chosen.name) — Enhanced"
            default: return "\(chosen.name) — compact; a downloaded Enhanced voice sounds better"
            }
        }
        // Automatic: read the warmed resolution instead of enumerating the
        // whole voice catalog during a body render — the first speechVoices()
        // call is slow and this computed property runs on every Settings
        // render (spec 029 R5). ChatService.prewarm warms the cache; if
        // Settings opens first, warm it here and show a neutral label until
        // the next render.
        if let quality = VoicePlaybackService.shared.resolvedVoiceQuality {
            return quality == .enhanced || quality == .premium
                ? "Automatic — best voice on this device"
                : "Compact voice — download an Enhanced voice for natural speech"
        }
        Task { await VoicePlaybackService.shared.warmVoiceCatalog() }
        return "Automatic"
    }

    /// The app lock, controllable after onboarding. `SecuritySettingsView`
    /// explains why this was structurally impossible until the encryption key
    /// was decoupled from the PIN.
    private var securitySection: some View {
        SettingsSection(title: "Security") {
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
    }

    private var securitySubtitle: String {
        switch SecurityService.shared.currentMode {
        case .faceID: return "\(SecurityService.shared.biometricType ?? "Face ID") and PIN"
        case .pin: return "PIN required to open"
        case .none: return "Off — anyone with your phone can read your journal"
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
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
    }

    /// "Your Data" (spec 023 R4): one section for the whole local-only story —
    /// profile, AI on-device toggle, privacy policy, data-usage explainer,
    /// and Delete Everything. No accounts, so no Sign Out.
    private var yourDataSection: some View {
        SettingsSection(title: "Your Data") {
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

            SettingsRowDivider()

            SettingsToggleRow(
                icon: "brain",
                title: "AI Features",
                subtitle: preferences.aiEnabled
                    ? "Generated on-device with Apple Intelligence"
                    : "AI disabled – data stays on device",
                isOn: $preferences.aiEnabled,
                accessibilityHint: preferences.aiEnabled
                    ? "Uses Apple's on-device AI. Double-tap to disable."
                    : "AI disabled, your data stays on device. Double-tap to enable."
            )

            // REQ-INT-004's Z0 pin. Shown only when AI is on: pinning where
            // generation runs is meaningless when nothing generates.
            //
            // Copy is deliberately about permission, not behaviour — "allows"
            // rather than "uses". Today there is no Private Cloud Compute leg on
            // this SDK, so wording that promised the toggle changed something
            // observable would be a claim the app can't currently honour. This
            // phrasing stays true both now and when the Z1 leg lands.
            if preferences.aiEnabled {
                SettingsRowDivider()

                SettingsToggleRow(
                    icon: "iphone.gen3",
                    title: "On-Device Only",
                    subtitle: preferences.processOnDeviceOnly
                        ? "Reflections and chat stay on this device"
                        : "Allows Apple's Private Cloud Compute for heavier requests",
                    isOn: $preferences.processOnDeviceOnly,
                    accessibilityHint: preferences.processOnDeviceOnly
                        ? "Generation stays on this device. Double-tap to allow Private Cloud Compute."
                        : "Private Cloud Compute is allowed for heavier requests. "
                            + "Double-tap to keep everything on this device."
                )
            }

            SettingsRowDivider()

            // Sample entries. Memento reflects on what you've written, so a
            // fresh install has nothing for Ask to work with — a weak first
            // impression, and a Guideline 2.1 risk since a reviewer opens the
            // app cold with an empty journal.
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

            SettingsRowDivider()

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

            SettingsRowDivider()

            SettingsRow(
                icon: "hand.raised",
                title: "Privacy Policy",
                subtitle: "How we protect your data",
                showChevron: true,
                action: {
                    UIApplication.shared.open(Constants.Legal.privacyPolicyURL)
                }
            )

            SettingsRowDivider()

            SettingsRow(
                icon: "info.circle",
                title: "What Data We Collect",
                subtitle: "Learn about data usage",
                showChevron: true,
                action: {
                    showDataUsageInfo = true
                }
            )

            SettingsRowDivider()

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
