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
        static let shareFeedbackWithDeveloper = PreferencesService.shareFeedbackKey
        static let dailyReminderEnabled = "dailyReminderEnabled"
        static let dailyReminderHour = "dailyReminderHour"
        static let dailyReminderMinute = "dailyReminderMinute"
        static let weeklyReadyEnabled = "weeklyReadyEnabled"
    }

    /// UserDefaults key for the spec 042 verification toggle. Read by the
    /// outbox from any queue; keep in sync with `shareFeedbackWithDeveloper`.
    static let shareFeedbackKey = "shareFeedbackWithDeveloper"

    // MARK: - Published Properties
    @Published var aiEnabled: Bool {
        didSet {
            defaults.set(aiEnabled, forKey: Keys.aiEnabled)
            LocalProfileStore.persistMirroredProfile()
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
            LocalProfileStore.persistMirroredProfile()
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

    /// Spec 042: opt-in so volunteered chat feedback may leave this device
    /// for quality verification. Off by default. Journal entries never sync.
    @Published var shareFeedbackWithDeveloper: Bool {
        didSet {
            defaults.set(shareFeedbackWithDeveloper, forKey: Keys.shareFeedbackWithDeveloper)
            if oldValue && !shareFeedbackWithDeveloper {
                FeedbackSyncService.shared.withdrawConsent()
            }
        }
    }

    /// Opt-in daily journal reminder (019 R8). Off by default.
    @Published var dailyReminderEnabled: Bool {
        didSet {
            defaults.set(dailyReminderEnabled, forKey: Keys.dailyReminderEnabled)
            Task { @MainActor in
                await NotificationService.shared.syncDailyReminder()
            }
        }
    }

    /// Hour of the daily reminder, 0...23. Default 20 (8:00 PM).
    @Published var dailyReminderHour: Int {
        didSet {
            defaults.set(dailyReminderHour, forKey: Keys.dailyReminderHour)
            Task { @MainActor in
                await NotificationService.shared.syncDailyReminder()
            }
        }
    }

    /// Minute of the daily reminder, 0...59. Default 0.
    @Published var dailyReminderMinute: Int {
        didSet {
            defaults.set(dailyReminderMinute, forKey: Keys.dailyReminderMinute)
            Task { @MainActor in
                await NotificationService.shared.syncDailyReminder()
            }
        }
    }

    /// Opt-in one-shot when a weekly reflection is saved. Off by default.
    @Published var weeklyReadyEnabled: Bool {
        didSet {
            defaults.set(weeklyReadyEnabled, forKey: Keys.weeklyReadyEnabled)
            if !weeklyReadyEnabled {
                Task { @MainActor in
                    NotificationService.shared.cancelWeeklyReady()
                }
            }
        }
    }

    var formattedDailyReminderTime: String {
        var components = DateComponents()
        components.hour = dailyReminderHour
        components.minute = dailyReminderMinute
        let date = Calendar.current.date(from: components) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
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
        self.shareFeedbackWithDeveloper =
            defaults.object(forKey: Keys.shareFeedbackWithDeveloper) as? Bool ?? false
        self.dailyReminderEnabled =
            defaults.object(forKey: Keys.dailyReminderEnabled) as? Bool ?? false
        self.dailyReminderHour = defaults.object(forKey: Keys.dailyReminderHour) as? Int ?? 20
        self.dailyReminderMinute = defaults.object(forKey: Keys.dailyReminderMinute) as? Int ?? 0
        self.weeklyReadyEnabled =
            defaults.object(forKey: Keys.weeklyReadyEnabled) as? Bool ?? false
    }

    /// Resets preferences to defaults. Used by "Delete everything" (spec 023 R4).
    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.themePreference)
        defaults.removeObject(forKey: Keys.aiEnabled)
        defaults.removeObject(forKey: Keys.processOnDeviceOnly)
        defaults.removeObject(forKey: Keys.selectedVoiceIdentifier)
        defaults.removeObject(forKey: Keys.speechRate)
        defaults.removeObject(forKey: Keys.shareFeedbackWithDeveloper)
        // Retired 2026-08-18 with the compact-voice nudge (spec 033 R6). Removed
        // here as well so "delete everything" does not leave an orphan behind —
        // resetToDefaults() never cleared this key even when it was live.
        defaults.removeObject(forKey: "compactVoiceNudgeDismissed")
        defaults.removeObject(forKey: Keys.dailyReminderEnabled)
        defaults.removeObject(forKey: Keys.dailyReminderHour)
        defaults.removeObject(forKey: Keys.dailyReminderMinute)
        defaults.removeObject(forKey: Keys.weeklyReadyEnabled)
        aiEnabled = true
        processOnDeviceOnly = false
        selectedVoiceIdentifier = nil
        speechRate = SpeechRatePreset.brisk.rawValue
        shareFeedbackWithDeveloper = false
        dailyReminderEnabled = false
        dailyReminderHour = 20
        dailyReminderMinute = 0
        weeklyReadyEnabled = false
        Task { @MainActor in
            NotificationService.shared.cancelAll()
        }
    }
}
