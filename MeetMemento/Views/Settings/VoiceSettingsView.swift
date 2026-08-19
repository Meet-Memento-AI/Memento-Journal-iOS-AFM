//
//  VoiceSettingsView.swift
//  MeetMemento
//
//  Read-aloud voice and speed. Exactly four voices, bundled in the app
//  (specs 030 R4, 033 R1/R5; DEC-011/DEC-012).
//
//  This screen used to enumerate AVSpeechSynthesisVoice.speechVoices() and list
//  the user's whole language family — 30-45 rows on a typical en-US device,
//  including en-AU/GB/IE/IN/NZ/ZA — plus an "Automatic" row and a "How to
//  download a voice" path into iOS Settings. All of that is gone. The voices
//  ship with the app, there is nothing to download, and the roster is fixed.
//
//  Modeled on AppearanceSettingsView: hand-built SettingsSection cards with
//  SettingsSelectableRow choices, persisted via PreferencesService.
//

import SwiftUI

public struct VoiceSettingsView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var selectedVoiceID: String = VoiceCatalog.default.id
    @State private var selectedRate: SpeechRatePreset = .brisk

    /// Previews own their audio session — they are one-shot and do not touch
    /// the conversation path's `.playAndRecord` negotiation (spec 028 R2).
    private static let playback = TTSPlayback(managesAudioSession: true)

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                SettingsSection(title: "Voice") {
                    ForEach(Array(VoiceCatalog.all.enumerated()), id: \.element.id) { index, voice in
                        SettingsSelectableRow(
                            icon: voice.symbol,
                            title: voice.displayName,
                            subtitle: voice.descriptor,
                            isSelected: selectedVoiceID == voice.id,
                            action: { select(voice: voice) }
                        )
                        .accessibilityIdentifier("settings.voice.option.\(voice.id)")

                        if index < VoiceCatalog.all.count - 1 {
                            SettingsRowDivider()
                        }
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
        .onAppear {
            loadCurrent()
            // Warm on appearance, not on first tap: opening this screen is a
            // voice-intent signal in exactly the sense spec 031 R3 means, and
            // ANE specialization on first load must not land on the first
            // preview the user asks to hear.
            Task { try? await SupertonicEngine.shared.prepare() }
        }
        // No willEnterForeground refresh: a fixed, bundled roster cannot change
        // while the app is backgrounded. The old screen needed it because a
        // voice downloaded in iOS Settings had to appear on return.
    }

    // MARK: - Actions

    private func loadCurrent() {
        // Resolves legacy AVSpeechSynthesisVoice identifiers, nil (the old
        // "Automatic"), and retired style ids — all silently (spec 033 R3).
        let resolved = VoiceCatalog.resolve(persistedID: PreferencesService.shared.selectedVoiceIdentifier)
        selectedVoiceID = resolved.id
        selectedRate = SpeechRatePreset.nearest(to: PreferencesService.shared.speechRate)

        // Write the resolved id back so the migration happens once, on first
        // sight, rather than being recomputed on every load.
        if PreferencesService.shared.selectedVoiceIdentifier != resolved.id {
            PreferencesService.shared.selectedVoiceIdentifier = resolved.id
        }
    }

    private func select(voice: VoiceOption) {
        selectedVoiceID = voice.id
        PreferencesService.shared.selectedVoiceIdentifier = voice.id
        preview(styleID: voice.id, speed: selectedRate.neuralSpeed)
    }

    /// Synthesizes the preview live in the selected voice (spec 033 R2).
    ///
    /// Live rather than a pre-rendered clip because the model is bundled — there
    /// is nothing to wait for — and because a build-time render is frozen at
    /// whatever rate it was made with, so it drifts the moment Speaking Speed
    /// changes. The preview's whole job is "what will this sound like for me".
    ///
    private func preview(styleID: String, speed: Float) {
        // Inherited from the `speakPreview()` this replaced: never talk over an
        // open mic. Settings is not reachable mid-dictation today, but the guard
        // is cheap and its absence would be a silent half-duplex violation
        // (spec 028 R2) rather than a visible bug.
        guard !SpeechService.shared.isRecording, !SpeechService.shared.isProcessing else { return }

        Task {
            do {
                let buffer = try await SupertonicEngine.shared.synthesize(
                    text: Self.previewSentence, styleID: styleID, speed: speed)
                Self.playback.flushAndStop()   // a new tap replaces the last preview
                try Self.playback.enqueue(buffer, onPlayed: {})
            } catch {
                // Silent in Release (spec 030 R5: the fallback is invisible),
                // loud in Debug. A silent voice swap is exactly how a Vocoder/MPS
                // prediction failure presented as "the system voice is talking"
                // rather than as an error, and cost hours to find.
                AppLogger.log("neural preview failed for \(styleID): \(error)", type: .error)
                #if DEBUG
                assertionFailure("neural preview failed for \(styleID): \(error)")
                #endif
            }
        }
    }

    /// Journaling register, deliberately — a voice auditioned on "the quick brown
    /// fox" tells you nothing about how it will read back a hard week.
    private static let previewSentence =
        "This is how I'll sound when I read your journal back to you."

    /// Picking a speed previews it — in the **selected voice**, at the **new
    /// rate** (spec 033 R2). This used to call `VoicePlaybackService.speakPreview()`,
    /// which was still `AVSpeechSynthesizer`: the four neural voices shipped, and
    /// this one row kept answering in the system voice.
    private func select(rate: SpeechRatePreset) {
        selectedRate = rate
        PreferencesService.shared.speechRate = rate.rawValue
        preview(styleID: selectedVoiceID, speed: rate.neuralSpeed)
    }

    // MARK: - Row copy

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
