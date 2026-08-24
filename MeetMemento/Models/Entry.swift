//
//  Entry.swift
//  MeetMemento
//
//  UI projection of a journal entry (spec 040). Persistence is SwiftData
//  `StoredEntry` mirrored to the user's CloudKit private DB. No Memento account.
//

import Foundation

/// Journal entry model for UI rendering. The device is the system of record;
/// CloudKit private DB is the user's replica, not a Memento server.
public struct Entry: Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    /// Whether this entry has a photo in `PhotoStorage`, keyed by `id`. Not a
    /// path/URL — the file location is fully deterministic from `id`, so a
    /// stored path would be redundant, driftable state.
    public var hasPhoto: Bool

    public init(
        id: UUID = UUID(),
        title: String = "",
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        hasPhoto: Bool = false
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.hasPhoto = hasPhoto
    }
}

// MARK: - UI Helpers

extension Entry {
    public var displayTitle: String {
        title.isEmpty ? "Untitled Entry" : title
    }

    public var excerpt: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "No text" }
        return String(trimmed.prefix(100))
    }
}

// MARK: - Sample Data for Previews

extension Entry {
    /// January 1st, 2026 date for sample entries
    private static func makeJan2026Date() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Sample entries for previews and mock data - computed to avoid static initialization issues
    public static var sampleEntries: [Entry] {
        let jan2026 = makeJan2026Date()
        return [
            Entry(
                title: "New Year Reflections",
                text: "Starting 2026 with clarity and purpose. I've been thinking about what truly matters to me and how I want to spend my time this year. The fresh start feels invigorating.",
                createdAt: jan2026
            ),
            Entry(
                title: "Goals for the Year",
                // Deliberately not phrased as a health or wellness goal. Sample
                // content ships in the binary, so it is content the app authors
                // — and App Store age rating turns on whether the app surfaces
                // health/treatment topics (docs/app-store/05 §1). Keep fixtures
                // in the register of an ordinary journal, not a wellness product.
                text: "This year I want to focus on learning something difficult, building deeper connections with friends and family, and paying attention to how I actually spend my days. Writing in this journal daily is my first step.",
                createdAt: jan2026
            ),
            Entry(
                title: "Morning Thoughts",
                text: "Woke up feeling energized and ready to embrace the new year. There's something magical about January 1st - a clean slate, endless possibilities, and the motivation to be my best self.",
                createdAt: jan2026
            )
        ]
    }
}

// MARK: - Type Alias

/// Type alias for clarity - UIEntry is the lightweight UI model
public typealias UIEntry = Entry
