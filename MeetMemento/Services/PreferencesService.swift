//
//  PreferencesService.swift
//  MeetMemento
//
//  User preferences for theme and feature toggles.
//

import Foundation
import Combine

/// User preferences service for app-wide settings
class PreferencesService: ObservableObject {
    static let shared = PreferencesService()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let themePreference = "themePreference"
        static let aiEnabled = "aiEnabled"
        static let processOnDeviceOnly = "processOnDeviceOnly"
        static let selectedVoiceIdentifier = "selectedVoiceIdentifier"
        static let speechRate = "speechRate"
    }

    // MARK: - Published Properties
    @Published var aiEnabled: Bool {
        didSet {
            defaults.set(aiEnabled, forKey: Keys.aiEnabled)
        }
    }

    /// `REQ-INT-004`'s Z0 pin: keep every generation on this device, never on
    /// Apple's Private Cloud Compute.
    ///
    /// Distinct from `aiEnabled`, which turns generation off entirely. This
    /// keeps it on and constrains *where* it runs, so "AI on, device only"
    /// is expressible — the state spec 022's forced-degradation cohort needs
    /// from the shipped app rather than a forked build.
    ///
    /// Read only by `ModelRouter` via the intelligence boundary, never
    /// per-surface, so no surface can accidentally escape it.
    ///
    /// Defaults to off: on the current SDK there is no Z1 leg to opt out of,
    /// so defaulting it on would imply the app was doing something it isn't.
    @Published var processOnDeviceOnly: Bool {
        didSet {
            defaults.set(processOnDeviceOnly, forKey: Keys.processOnDeviceOnly)
        }
    }

    /// Read-aloud voice choice (spec 018 R7). nil = Automatic: the best
    /// Enhanced/Premium voice on the device via
    /// `VoicePlaybackService.bestVoice()`. Stores an
    /// `AVSpeechSynthesisVoice.identifier`; a since-deleted voice resolves to
    /// nil at playback time and falls back to Automatic.
    @Published var selectedVoiceIdentifier: String? {
        didSet {
            if let selectedVoiceIdentifier {
                defaults.set(selectedVoiceIdentifier, forKey: Keys.selectedVoiceIdentifier)
            } else {
                defaults.removeObject(forKey: Keys.selectedVoiceIdentifier)
            }
        }
    }

    /// Read-aloud speaking rate (AVSpeechUtterance.rate). Default 0.53 —
    /// `SpeechRatePreset.brisk`, the tuned value the feature shipped with.
    @Published var speechRate: Float {
        didSet {
            defaults.set(speechRate, forKey: Keys.speechRate)
        }
    }

    // MARK: - Theme Preference
    var themePreference: AppThemePreference {
        get {
            let rawValue = defaults.string(forKey: Keys.themePreference) ?? "system"
            return AppThemePreference(rawValue: rawValue) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.themePreference)
        }
    }

    // MARK: - Initialization
    private init() {
        // Initialize aiEnabled from stored value, default to true
        let storedEnabled = defaults.object(forKey: Keys.aiEnabled) as? Bool
        self.aiEnabled = storedEnabled ?? true
        self.processOnDeviceOnly = defaults.object(forKey: Keys.processOnDeviceOnly) as? Bool ?? false
        self.selectedVoiceIdentifier = defaults.string(forKey: Keys.selectedVoiceIdentifier)
        self.speechRate = defaults.object(forKey: Keys.speechRate) as? Float
            ?? SpeechRatePreset.brisk.rawValue
    }

    /// Resets preferences to defaults. Used by "Delete everything" (spec 023 R4).
    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.themePreference)
        defaults.removeObject(forKey: Keys.aiEnabled)
        defaults.removeObject(forKey: Keys.processOnDeviceOnly)
        defaults.removeObject(forKey: Keys.selectedVoiceIdentifier)
        defaults.removeObject(forKey: Keys.speechRate)
        // Retired 2026-08-18 with the compact-voice nudge (spec 033 R6). Removed
        // here as well so "delete everything" does not leave an orphan behind —
        // resetToDefaults() never cleared this key even when it was live.
        defaults.removeObject(forKey: "compactVoiceNudgeDismissed")
        aiEnabled = true
        processOnDeviceOnly = false
        selectedVoiceIdentifier = nil
        speechRate = SpeechRatePreset.brisk.rawValue
    }
}
