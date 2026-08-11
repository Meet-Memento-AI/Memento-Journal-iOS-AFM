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
    }

    // MARK: - Published Properties
    @Published var aiEnabled: Bool {
        didSet {
            defaults.set(aiEnabled, forKey: Keys.aiEnabled)
        }
    }

    /// The user's Z0 pin (spec 017 R2 / REQ-INT-004): when true, `ModelRouter`
    /// resolves EVERY intent to `.z0Device` before any PCC seam is consulted —
    /// a router-level override, never a per-surface setting. Default false
    /// (routing follows the table). Inert until the Private Cloud Compute
    /// path activates (iOS 27 SDK), but wired now so no surface can escape it.
    @Published var processOnDeviceOnly: Bool {
        didSet {
            defaults.set(processOnDeviceOnly, forKey: Keys.processOnDeviceOnly)
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
    }

    /// Resets preferences to defaults. Used by "Delete everything" (spec 023 R4).
    func resetToDefaults() {
        defaults.removeObject(forKey: Keys.themePreference)
        defaults.removeObject(forKey: Keys.aiEnabled)
        defaults.removeObject(forKey: Keys.processOnDeviceOnly)
        aiEnabled = true
        processOnDeviceOnly = false
    }
}
