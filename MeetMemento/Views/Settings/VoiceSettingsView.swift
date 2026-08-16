//
//  VoiceSettingsView.swift
//  MeetMemento
//
//  Read-aloud voice and speed (spec 018 R7 chat amendment; REQ-VOX-001's
//  "voice-asset download surfaced in Settings — never a silent fallback").
//  Modeled on AppearanceSettingsView: hand-built SettingsSection cards with
//  SettingsSelectableRow choices, persisted via PreferencesService.
//

import SwiftUI
import AVFoundation

public struct VoiceSettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    /// Non-novelty, non-personal voices for the user's language family:
    /// exact locale first, then same-prefix siblings (en-GB for en-US…),
    /// best quality first within each group.
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var selectedIdentifier: String?
    @State private var selectedRate: SpeechRatePreset = .brisk
    @State private var showDownloadHelp = false

    public init() {}

    /// True when nothing installed beats the compact default — the exact
    /// state R7's acceptance criterion says must never pass silently.
    private var onlyCompactAvailable: Bool {
        !voices.contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Voice") {
                    if onlyCompactAvailable {
                        SettingsInfoRow(
                            icon: "waveform.badge.exclamationmark",
                            title: "Compact voice",
                            description: "Download an Enhanced voice for natural speech. It's free, works offline, and Memento picks it up automatically."
                        )
                        SettingsRowDivider()
                        SettingsRow(
                            icon: "arrow.down.circle",
                            title: "How to download a voice",
                            subtitle: "Settings > Accessibility > Spoken Content > Voices",
                            showChevron: true,
                            accessibilityIdentifier: "settings.voice.downloadHelp",
                            action: { showDownloadHelp = true }
                        )
                        SettingsRowDivider()
                    }

                    SettingsSelectableRow(
                        icon: "wand.and.stars",
                        title: "Automatic",
                        subtitle: "The best voice on this device",
                        isSelected: selectedIdentifier == nil,
                        action: { select(identifier: nil) }
                    )
                    .accessibilityIdentifier("settings.voice.automatic")

                    ForEach(voices, id: \.identifier) { voice in
                        SettingsRowDivider()
                        SettingsSelectableRow(
                            icon: "person.wave.2",
                            title: voice.name,
                            subtitle: subtitle(for: voice),
                            isSelected: selectedIdentifier == voice.identifier,
                            action: { select(identifier: voice.identifier) }
                        )
                        .accessibilityIdentifier("settings.voice.option.\(voice.identifier)")
                    }
                }

                SettingsSection(title: "Speaking Speed") {
                    ForEach(Array(SpeechRatePreset.allCases.enumerated()), id: \.element) { index, preset in
                        SettingsSelectableRow(
                            icon: iconForPreset(preset),
                            title: preset.displayName,
                            subtitle: preset.subtitle,
                            isSelected: selectedRate == preset,
                            action: { select(rate: preset) }
                        )
                        .accessibilityIdentifier("settings.voice.rate.\(preset.displayName.lowercased())")

                        if index < SpeechRatePreset.allCases.count - 1 {
                            SettingsRowDivider()
                        }
                    }
                }

                Spacer(minLength: Spacing.xxxl)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.xs)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("Read Aloud")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadCurrent() }
        // A voice downloaded in the Settings app appears when the user
        // returns — no restart (R7 acceptance: picked up automatically).
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            loadCurrent()
            VoicePlaybackService.shared.invalidateVoiceCache()
        }
        .alert("Download a Voice", isPresented: $showDownloadHelp) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Download a natural voice in Settings > Accessibility > Spoken Content > Voices, then come back — Memento picks it up automatically.")
        }
    }

    // MARK: - Actions

    private func loadCurrent() {
        selectedIdentifier = PreferencesService.shared.selectedVoiceIdentifier
        selectedRate = SpeechRatePreset.nearest(to: PreferencesService.shared.speechRate)

        // First speechVoices() call can be slow — keep it out of `body`.
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = (language.split(separator: "-").first.map(String.init) ?? language) + "-"
        let family = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(prefix)
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                // Personal Voice stays unlisted until spec 018 R8's gate clears.
                && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        voices = family.sorted { a, b in
            if (a.language == language) != (b.language == language) {
                return a.language == language
            }
            if a.quality != b.quality {
                return a.quality.rawValue > b.quality.rawValue
            }
            return a.name < b.name
        }
    }

    private func select(identifier: String?) {
        selectedIdentifier = identifier
        PreferencesService.shared.selectedVoiceIdentifier = identifier
        VoicePlaybackService.shared.speakPreview()
    }

    private func select(rate: SpeechRatePreset) {
        selectedRate = rate
        PreferencesService.shared.speechRate = rate.rawValue
        VoicePlaybackService.shared.speakPreview()
    }

    // MARK: - Row copy

    private func subtitle(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium: quality = "Premium"
        case .enhanced: quality = "Enhanced"
        default: quality = "Compact"
        }
        let region = Locale.current.localizedString(forIdentifier: voice.language)
            ?? voice.language
        return "\(quality) · \(region)"
    }

    private func iconForPreset(_ preset: SpeechRatePreset) -> String {
        switch preset {
        case .slower: return "tortoise"
        case .normal: return "figure.walk"
        case .brisk: return "figure.walk.motion"
        case .fast: return "hare"
        }
    }
}

#Preview {
    NavigationStack {
        VoiceSettingsView()
            .useTheme()
            .useTypography()
    }
}
