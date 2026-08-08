//
//  Entry.swift
//  MeetMemento
//
//  The journal entry model used throughout the app. The app is on-device only
//  (no accounts, no backend), so this is the single entry model — persisted as
//  an encrypted local envelope by JournalService. (A separate server DTO used
//  to exist for the Supabase backend; it was removed with the backend.)
//

import Foundation

/// Journal entry model for UI rendering and local persistence.
public struct Entry: Identifiable, Hashable {
    /// Whether this entry has reached the server yet (spec-007: local-first writes).
    public enum SyncStatus: Hashable {
        /// Confirmed on the server.
        case synced
        /// Saved locally; still queued to reach the server (offline, or a
        /// transient failure being retried on reconnect).
        case pending
    }

    public let id: UUID
    public var title: String
    public var text: String
    public var createdAt: Date
    public var updatedAt: Date
    public var syncStatus: SyncStatus

    public init(
        id: UUID = UUID(),
        title: String = "",
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        syncStatus: SyncStatus = .synced
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncStatus = syncStatus
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
                text: "This year I want to focus on personal growth, building deeper connections with friends and family, and taking better care of my mental health. Writing in this journal daily is my first step.",
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
