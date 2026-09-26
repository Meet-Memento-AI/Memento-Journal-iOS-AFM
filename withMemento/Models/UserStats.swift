
import Foundation

/// Represents user statistics from the `user_stats` table.
public struct UserStats: Codable, Hashable {
    public let userId: UUID
    public var totalEntries: Int
    public var totalWords: Int
    public var currentStreak: Int
    public var longestStreak: Int
    public var lastStreakCheckDate: Date? // date (YYYY-MM-DD) in DB, mapped to Date here
    public var firstEntryDate: Date?
    public var lastEntryDate: Date?
    public var entriesThisWeek: Int
    public var entriesThisMonth: Int
    public var entriesThisYear: Int
    public var avgWordsPerEntry: Int
    public var avgEntriesPerWeek: Double // numeric in DB

    public let createdAt: Date
    public var updatedAt: Date
    public var lastRecalculatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case totalEntries = "total_entries"
        case totalWords = "total_words"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastStreakCheckDate = "last_streak_check_date"
        case firstEntryDate = "first_entry_date"
        case lastEntryDate = "last_entry_date"
        case entriesThisWeek = "entries_this_week"
        case entriesThisMonth = "entries_this_month"
        case entriesThisYear = "entries_this_year"
        case avgWordsPerEntry = "avg_words_per_entry"
        case avgEntriesPerWeek = "avg_entries_per_week"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastRecalculatedAt = "last_recalculated_at"
    }
}

// MARK: - Mocks
extension UserStats {
    public static let mock = UserStats(
        userId: UUID(),
        totalEntries: 42,
        totalWords: 1500,
        currentStreak: 5,
        longestStreak: 12,
        lastStreakCheckDate: Date(),
        firstEntryDate: Date().addingTimeInterval(-86400 * 30),
        lastEntryDate: Date(),
        entriesThisWeek: 3,
        entriesThisMonth: 12,
        entriesThisYear: 42,
        avgWordsPerEntry: 35,
        avgEntriesPerWeek: 3.5,
        createdAt: Date(),
        updatedAt: Date(),
        lastRecalculatedAt: Date()
    )
}
