//
//  ChatSession.swift
//  MeetMemento
//
//  Data model for chat session history
//

import Foundation

/// Represents a past chat session for history display
public struct ChatSession: Identifiable, Hashable, Codable {
    public let id: UUID
    /// The first message sent by the user (used as session title)
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)

        // Parse ISO8601 date strings from the local store
        let createdAtString = try container.decode(String.self, forKey: .createdAt)
        let updatedAtString = try container.decode(String.self, forKey: .updatedAt)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: createdAtString) {
            createdAt = date
        } else {
            // Fallback without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            createdAt = formatter.date(from: createdAtString) ?? Date()
        }

        if let date = formatter.date(from: updatedAtString) {
            updatedAt = date
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            updatedAt = formatter.date(from: updatedAtString) ?? createdAt
        }
    }
}

// MARK: - DTO for chat messages from the local store

public struct ChatMessageDTO: Codable {
    public let id: UUID
    public let role: String
    public let content: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case createdAt = "created_at"
    }
}

// MARK: - Mock Data

extension ChatSession {
    /// Mock sessions for UI development (titles are first user messages)
    static let mockSessions: [ChatSession] = [
        ChatSession(
            title: "What patterns do you see in my recent journal entries?",
            createdAt: Date().addingTimeInterval(-3600 * 2),
            updatedAt: Date().addingTimeInterval(-3600)
        ),
        ChatSession(
            title: "Help me understand my stress triggers from last week",
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date().addingTimeInterval(-86400)
        ),
        ChatSession(
            title: "Analyze my morning routine entries and their impact",
            createdAt: Date().addingTimeInterval(-86400 * 3),
            updatedAt: Date().addingTimeInterval(-86400 * 2)
        ),
        ChatSession(
            title: "What have I written about my friendships lately?",
            createdAt: Date().addingTimeInterval(-86400 * 7),
            updatedAt: Date().addingTimeInterval(-86400 * 7)
        ),
        ChatSession(
            title: "Summarize my mood patterns over the past month",
            createdAt: Date().addingTimeInterval(-86400 * 14),
            updatedAt: Date().addingTimeInterval(-86400 * 14)
        )
    ]
}
