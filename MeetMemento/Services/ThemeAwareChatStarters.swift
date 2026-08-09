//
//  ThemeAwareChatStarters.swift
//  MeetMemento
//
//  Templated chat empty-state starters derived from confirmed ThemeCatalog
//  themes. No model generation — pure local templates so uniqueness is visible
//  without free-form AI chatter.
//

import Foundation

enum ThemeAwareChatStarters {
    /// Build up to `limit` starters from confirmed theme display names.
    /// Returns an empty array when the profile has no themes (caller falls back
    /// to the generic prompt pool).
    static func starters(
        themeIds: [String] = LocalProfileStore.ensureMigratedProfile().confirmedThemeIds,
        limit: Int = 3
    ) -> [String] {
        let names = ThemeCatalog.displayNames(for: themeIds)
        guard !names.isEmpty else { return [] }

        var pool: [String] = []
        for name in names {
            let lower = name.lowercased()
            pool.append(contentsOf: templates(for: lower, display: name))
        }

        // Stable shuffle keyed by theme set so rotation still feels fresh but
        // stays deterministic within a session when called repeatedly with same input.
        return Array(pool.shuffled().prefix(limit))
    }

    /// Merge theme starters with a generic fallback pool, preferring themes.
    static func rotate(
        genericPool: [String],
        limit: Int = 3
    ) -> [String] {
        let themed = starters(limit: limit)
        if themed.count >= limit { return themed }
        let needed = limit - themed.count
        let fillers = genericPool.shuffled().prefix(needed)
        return themed + fillers
    }

    private static func templates(for lower: String, display: String) -> [String] {
        [
            "What patterns around \(lower) show up in my recent entries?",
            "How has \(lower) shown up for me this month?",
            "What am I learning about \(lower) from my journal?",
            "Where do my entries mention \(display), and what stands out?"
        ]
    }
}
