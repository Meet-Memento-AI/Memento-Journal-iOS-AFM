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
