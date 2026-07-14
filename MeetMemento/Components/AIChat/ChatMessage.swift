//
//  ChatMessage.swift
//  MeetMemento
//
//  Data model for chat messages in AI Chat interface
//

import Foundation

/// Inline citation info for displaying numbered references in the body text
public struct InlineCitationInfo: Identifiable, Hashable {
    public var id: Int { ref }
    public let ref: Int
    public let entryId: UUID
    public let theme: String
    public let entryDate: Date
    public let excerpt: String

    public init(
        ref: Int,
        entryId: UUID,
        theme: String,
        entryDate: Date,
        excerpt: String
    ) {
        self.ref = ref
        self.entryId = entryId
        self.theme = theme
        self.entryDate = entryDate
        self.excerpt = excerpt
    }
}

/// Citation reference to a journal entry (for future use)
public struct JournalCitation: Identifiable, Hashable, Codable {
    public let id: UUID
    public let entryId: UUID
    public let entryTitle: String
    public let entryDate: Date
    public let excerpt: String

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case entryTitle = "entry_title"
        case entryDate = "entry_date"
        case excerpt
    }

    public init(
        id: UUID = UUID(),
        entryId: UUID,
        entryTitle: String,
        entryDate: Date,
        excerpt: String
    ) {
        self.id = id
        self.entryId = entryId
        self.entryTitle = entryTitle
        self.entryDate = entryDate
        self.excerpt = excerpt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idString = try? container.decodeIfPresent(String.self, forKey: .id),
           let uuid = UUID(uuidString: idString) {
            id = uuid
        } else {
            id = UUID()
        }
        if let entryIdString = try? container.decodeIfPresent(String.self, forKey: .entryId),
           let uuid = UUID(uuidString: entryIdString) {
            entryId = uuid
        } else {
            entryId = UUID()
        }
        entryTitle = try container.decodeIfPresent(String.self, forKey: .entryTitle) ?? ""
        let dateString = try container.decodeIfPresent(String.self, forKey: .entryDate) ?? ""
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        entryDate = fmt.date(from: dateString)
            ?? ISO8601DateFormatter().date(from: dateString)
            ?? Date()
        excerpt = try container.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(entryId.uuidString, forKey: .entryId)
        try container.encode(entryTitle, forKey: .entryTitle)
        try container.encode(ISO8601DateFormatter().string(from: entryDate), forKey: .entryDate)
        try container.encode(excerpt, forKey: .excerpt)
    }
}

/// Feedback type for AI responses (thumbs up/down)
public enum FeedbackType: String, Hashable, Codable {
    case positive
    case negative
}

/// Chat message model for AI Chat interface
public struct ChatMessage: Identifiable, Hashable {
    public let id: UUID
    public let content: String
    public let isFromUser: Bool
    public let timestamp: Date
    public let citations: [JournalCitation]?

    // Structured content for AI messages (optional)
    public let aiOutputContent: AIOutputContent?

    /// True for messages created in the current session (should animate).
    /// False for messages loaded from database (should display instantly).
    public let isNew: Bool

    public init(
        id: UUID = UUID(),
        content: String,
        isFromUser: Bool,
        timestamp: Date = Date(),
        citations: [JournalCitation]? = nil,
        aiOutputContent: AIOutputContent? = nil,
        isNew: Bool = false
    ) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.citations = citations
        self.aiOutputContent = aiOutputContent
        self.isNew = isNew
    }
    
    // Convenience initializer for AI messages with structured content
    public static func aiMessage(
        id: UUID = UUID(),
        heading1: String? = nil,
        heading2: String? = nil,
        body: String,
        citations: [JournalCitation]? = nil,
        timestamp: Date = Date(),
        isNew: Bool = false
    ) -> ChatMessage {
        let outputContent = AIOutputContent(
            heading1: heading1,
            heading2: heading2,
            body: body,
            citations: citations
        )
        return ChatMessage(
            id: id,
            content: body, // Keep content for backwards compatibility
            isFromUser: false,
            timestamp: timestamp,
            citations: citations,
            aiOutputContent: outputContent,
            isNew: isNew
        )
    }
}
