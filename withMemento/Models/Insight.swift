//
//  Insight.swift
//  MeetMemento
//
//  Minimal stub models for Insights (UI boilerplate).
//

import Foundation

/// Stub model for insight annotations
public struct InsightAnnotation: Identifiable, Hashable {
    public let id: UUID
    public let date: String  // ISO8601 date string for simplicity
    public let summary: String

    public init(id: UUID = UUID(), date: String = "", summary: String = "") {
        self.id = id
        self.date = date
        self.summary = summary
    }
}

/// Stub model for identified themes
public struct IdentifiedTheme: Identifiable, Hashable {
    public let id: UUID
    public let name: String
    public let title: String
    public let summary: String
    public let keywords: [String]
    public let emoji: String
    public let category: String
    public let color: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        title: String = "",
        summary: String = "",
        keywords: [String] = [],
        emoji: String = "🌟",
        category: String = "",
        color: String = "blue"
    ) {
        self.id = id
        self.name = name
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.emoji = emoji
        self.category = category
        self.color = color
    }
}

/// Theme preference enum
public enum AppThemePreference: String, CaseIterable {
    case system
    case light
    case dark

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .light: return "Light Mode"
        case .dark: return "Dark Mode"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let themePreferenceChanged = Notification.Name("themePreferenceChanged")
}
