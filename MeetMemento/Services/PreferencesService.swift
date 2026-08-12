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
