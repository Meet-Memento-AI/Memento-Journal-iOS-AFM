//
//  ThemeAwareChatStarters.swift
//  MeetMemento
//
//  Templated chat empty-state starters derived from confirmed ThemeCatalog
//  themes. No model generation — pure local templates so uniqueness is visible
//  without free-form AI chatter.
//

import Foundation

/// One empty-state starter: the prompt to send, plus the confirmed catalog
/// theme shown on the card's pill. `themeName` is nil when the profile has
/// no confirmed themes.
struct ChatSuggestion: Hashable, Identifiable {
    let id: UUID
    let prompt: String
    let themeName: String?

    init(prompt: String, themeName: String?, id: UUID = UUID()) {
        self.id = id
        self.prompt = prompt
        self.themeName = themeName
    }

    /// Canvas-only starters so AIChatView previews show pills without writing
    /// a profile into UserDefaults.
    static let previewSamples: [ChatSuggestion] = [
        ChatSuggestion(
            prompt: "Summarize the key themes and emotions from my journal entries this month",
            themeName: "Mindfulness"
        ),
        ChatSuggestion(
            prompt: "Create an actionable plan based on my recent habits and daily patterns",
            themeName: "Goals"
        ),
        ChatSuggestion(
            prompt: "How has my mood shifted over the past two weeks?",
            themeName: "Sleep"
        )
    ]

    /// Shown under the empty-state headline when rotation has not produced
    /// chips yet, so the three tiles never vanish. Pills always render.
    static let fallbackStarters: [ChatSuggestion] = [
        ChatSuggestion(
            prompt: "Summarize the key themes and emotions from my journal entries this month",
            themeName: "Mindfulness"
        ),
        ChatSuggestion(
            prompt: "Create an actionable plan based on my recent habits and daily patterns",
            themeName: "Goals"
        ),
        ChatSuggestion(
            prompt: "How has my mood shifted over the past two weeks?",
            themeName: "Sleep"
        )
    ]
}

enum ThemeAwareChatStarters {
    /// Build up to `limit` starters from confirmed theme display names.
    /// Returns an empty array when the profile has no themes (caller falls back
    /// to the generic prompt pool).
    static func starters(
        themeIds: [String] = LocalProfileStore.ensureMigratedProfile().confirmedThemeIds,
        limit: Int = 3
    ) -> [ChatSuggestion] {
        let names = ThemeCatalog.displayNames(for: themeIds)
        guard !names.isEmpty else { return [] }

        var pool: [ChatSuggestion] = []
        for name in names {
            let lower = name.lowercased()
            for template in templates(for: lower, display: name) {
                pool.append(ChatSuggestion(prompt: template, themeName: name))
            }
        }

        // Stable shuffle keyed by theme set so rotation still feels fresh but
        // stays deterministic within a session when called repeatedly with same input.
        return Array(pool.shuffled().prefix(limit))
    }

    /// Merge theme starters with a generic fallback pool.
    /// At most one themed chip; the rest come from the generic pool so the
    /// empty state is not three "tell me about {goal}" prompts.
    /// Generic fillers still get a pill from the user's remaining confirmed themes.
    static func rotate(
        genericPool: [String],
        limit: Int = 3
    ) -> [ChatSuggestion] {
        let themeNames = ThemeCatalog.displayNames(
            for: LocalProfileStore.ensureMigratedProfile().confirmedThemeIds
        )
        let themed = starters(limit: 1)
        var result: [ChatSuggestion] = []
        var usedThemes: Set<String> = []
        if let first = themed.first {
            result.append(first)
            if let theme = first.themeName { usedThemes.insert(theme) }
        }
        let leftoverThemes = themeNames.filter { !usedThemes.contains($0) }
        let pillNames = themeNames.isEmpty ? Self.defaultPillNames : themeNames
        var themeCursor = 0
        let needed = max(limit - result.count, 0)
        for prompt in genericPool.shuffled().prefix(needed) {
            let theme: String
            if leftoverThemes.isEmpty {
                theme = pillNames[themeCursor % pillNames.count]
            } else if themeCursor < leftoverThemes.count {
                theme = leftoverThemes[themeCursor]
            } else {
                theme = pillNames[themeCursor % pillNames.count]
            }
            themeCursor += 1
            result.append(ChatSuggestion(prompt: prompt, themeName: theme))
        }
        return Array(result.prefix(limit))
    }

    /// Pills on the empty-state tiles when the profile has no confirmed themes.
    private static let defaultPillNames = ["Mindfulness", "Goals", "Sleep"]

    private static func templates(for lower: String, display: String) -> [String] {
        [
            "What patterns around \(lower) show up in my recent entries?",
            "How has \(lower) shown up for me this month?",
            "What am I learning about \(lower) from my journal?",
            "Where do my entries mention \(display), and what stands out?"
        ]
    }
}
