//
//  RevenueCatConfig.swift
//  withMemento
//
//  Spec 021 R3: the RevenueCat public SDK key, read from Info.plist
//  (REVENUECAT_API_KEY ← Config/*.xcconfig). Missing key → not configured,
//  and EntitlementStore stays off (nothing is Pro, nothing crashes).
//

import Foundation

enum RevenueCatConfig {
    /// Master switch for Memento Pro. Off: the SDK is never configured, so it
    /// makes no network calls. Every paid surface is open, and Settings shows
    /// no Pro section. This is the same fail-open path as a missing key.
    /// Flip to `true` to turn the paywall back on.
    static let isPaywallEnabled = false

    /// Whether RevenueCat runs this launch: the master switch, or in DEBUG
    /// builds the `-EnablePaywall` launch argument, which runs the whole live
    /// flow against RevenueCat's Test Store (the Debug `test_` key) for QA and
    /// end-to-end verification without flipping the switch. Release builds
    /// only ever follow `isPaywallEnabled`.
    static var isActive: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-EnablePaywall") { return true }
        #endif
        return isPaywallEnabled
    }

    static func apiKeyFromBundle(_ bundle: Bundle = .main) -> String? {
        resolve(bundle.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String)
    }

    /// Pure so the rules are testable without rebuilding against other
    /// xcconfig values (same reasoning as `FeedbackSupabaseConfig.resolve`).
    static func resolve(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        // An unexpanded build variable means the xcconfig never supplied one.
        if trimmed.hasPrefix("$(") { return nil }
        return trimmed
    }
}
