//
//  MockDataProvider.swift
//  MeetMemento
//
//  Mock data provider for UI development without a live data source.
//  Active when USE_MOCK_DATA flag is set.
//

import Foundation

#if USE_MOCK_DATA

/// Mock data provider for UI testing
class MockDataProvider {
    static let shared = MockDataProvider()

    private init() {}

    // MARK: - Mock User Data

    var mockUserFirstName = "Alex"
    var mockUserLastName = "Johnson"
    var mockUserEmail = "alex.johnson@example.com"

    // MARK: - Mock Journal Entries

    var mockEntries: [Entry] = [
        Entry(
            id: UUID(),
            title: "Project Completion",
            text: "Today was a great day! I finally finished the project I've been working on for weeks. The sense of accomplishment is incredible. I celebrated by going for a long walk in the park and treating myself to my favorite coffee.",
            createdAt: Date().addingTimeInterval(-86400 * 2) // 2 days ago
        ),
        Entry(
            id: UUID(),
            title: "Staying Focused",
            text: "Feeling a bit overwhelmed with all the tasks ahead. Need to prioritize and take things one step at a time. Remember to breathe and stay focused on what matters most.",
            createdAt: Date().addingTimeInterval(-86400 * 5) // 5 days ago
        ),
        Entry(
            id: UUID(),
            title: "Grateful Connection",
            text: "Had an inspiring conversation with a friend today. It reminded me why I started this journey in the first place. Grateful for the people who support and encourage me.",
            createdAt: Date().addingTimeInterval(-86400 * 10) // 10 days ago
        ),
        Entry(
            id: UUID(),
            title: "Morning Meditation",
            text: "Trying something new today - morning meditation. It was challenging to quiet my mind at first, but I'm committed to making this a daily habit. Small steps lead to big changes.",
            createdAt: Date().addingTimeInterval(-86400 * 15) // 15 days ago
        ),
        Entry(
            id: UUID(),
            title: "Monthly Reflection",
            text: "Reflected on my goals for this month. Some progress made, but there's still work to do. The important thing is to keep moving forward and not get discouraged by setbacks.",
            createdAt: Date().addingTimeInterval(-86400 * 30) // 30 days ago
        )
    ]

    // MARK: - Mock Authentication

    var isAuthenticated = true
    var hasCompletedOnboarding = true

    // MARK: - Helper Methods

    func addMockEntry(_ entry: Entry) {
        mockEntries.insert(entry, at: 0)
    }

    func deleteMockEntry(id: UUID) {
        mockEntries.removeAll { $0.id == id }
    }

    func updateMockEntry(_ entry: Entry) {
        if let index = mockEntries.firstIndex(where: { $0.id == entry.id }) {
            mockEntries[index] = entry
        }
    }
}

#endif
