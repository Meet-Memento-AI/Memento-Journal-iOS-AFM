//
//  ExperienceProfile.swift
//  MeetMemento
//
//  Local per-user personalization produced during onboarding:
//  reflection seed + confirmed ThemeCatalog ids + bounded prompt lens.
//

import Foundation

struct ExperienceProfile: Codable, Equatable, Sendable {
    var reflection: String?
    /// Confirmed theme ids from ThemeCatalog (user-edited).
    var confirmedThemeIds: [String]
    /// AFM (or keyword) suggestions from the last estimate, for audit/debug.
    var suggestedThemeIds: [String]
    /// Bounded personalization instructions injected into ask prompts.
    var promptLens: String?
    var catalogVersion: String
    var builtAt: Date
    /// `REQ-PRM-004` provenance: which model and which prompt produced
    /// `promptLens`. Without both, a stored lens cannot be attributed and spec
    /// 022's quality study cannot explain a regression in it. Optional so
    /// profiles written before this existed still decode.
    var modelIdentifier: String?
    var promptVersion: String?

    static let empty = ExperienceProfile(
        reflection: nil,
        confirmedThemeIds: [],
        suggestedThemeIds: [],
        promptLens: nil,
        catalogVersion: ThemeCatalog.catalogVersion,
        builtAt: .distantPast,
        modelIdentifier: nil,
        promptVersion: nil
    )

    var isEmpty: Bool {
        let reflectionEmpty = reflection?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return reflectionEmpty && confirmedThemeIds.isEmpty && (promptLens?.isEmpty ?? true)
    }

    /// Display names for confirmed themes, resolved through the catalog.
    var confirmedThemeNames: [String] {
        ThemeCatalog.displayNames(for: confirmedThemeIds)
    }
}
