//
//  ChatMessage.swift
//  withMemento
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

    /// JPEG bytes for photos the user attached to this turn. Empty for
    /// assistant messages and for text-only user turns. In-memory for the
    /// current session so follow-ups can still see the pixels; not persisted
    /// with the transcript store (those files stay small and text-only).
    public var imageJPEGs: [Data]

    // Structured content for AI messages (optional)
    public let aiOutputContent: AIOutputContent?

    /// Spec 026: how this assistant turn was safety-routed (crisis card / hard refuse).
    public var safetyPresentation: ChatSafetyPresentation

    /// True for messages created in the current session (should animate).
    /// False for messages loaded from database (should display instantly).
    /// Mutable so the view model can mark a message as "seen" once its
    /// entrance animation has played — otherwise LazyVStack recycling and
    /// tab switches replay the typewriter effect on the whole transcript.
    public var isNew: Bool

    /// True for this user message failed to send (spec-010): kept visible
    /// in the transcript with a retry affordance instead of being dropped.
    public var sendFailed: Bool

    /// True while this assistant message is still receiving streamed deltas.
    /// Transient (never persisted) — mirrors `isNew`. The typewriter uses it to
    /// know the stream has truly ended (vs. a mid-generation pause) so it only
    /// completes once the full reply has been drained.
    public var isStreaming: Bool

    /// Spec 041: generation metadata copied from the stored assistant JSON so
    /// a reported turn can be attributed (REQ-PRM-004). Optional — older
    /// transcripts and in-session streams may not have them yet.
    public var promptVersion: String?
    public var modelIdentifier: String?
    public var zone: String?
    public var wasDegraded: Bool?

    /// True for the question a suggestion card asked on the person's behalf.
    ///
    /// Such a message renders like a user bubble but **is not a user turn**,
    /// and `isFromUser` stays `false` for it. The distinction is load-bearing:
    /// `ChatService.summarizeChat` turns the transcript into a journal entry,
    /// so a card's question filed as the person's turn would be written into
    /// their own journal as a sentence they never wrote.
    ///
    /// `false` is not the same as "assistant" here either — `summarizeChat`
    /// drops these messages entirely rather than filing them under either
    /// role, because the assistant did not say it and neither did the person.
    /// `StarterOpensConversationTests` pins both halves of that.
    public var isStarterPrompt: Bool

    public init(
        id: UUID = UUID(),
        content: String,
        isFromUser: Bool,
        timestamp: Date = Date(),
        citations: [JournalCitation]? = nil,
        imageJPEGs: [Data] = [],
        aiOutputContent: AIOutputContent? = nil,
        safetyPresentation: ChatSafetyPresentation = .none,
        isNew: Bool = false,
        sendFailed: Bool = false,
        isStreaming: Bool = false,
        isStarterPrompt: Bool = false,
        promptVersion: String? = nil,
        modelIdentifier: String? = nil,
        zone: String? = nil,
        wasDegraded: Bool? = nil
    ) {
        self.id = id
        self.content = content
        self.isFromUser = isFromUser
        self.timestamp = timestamp
        self.citations = citations
        self.imageJPEGs = imageJPEGs
        self.aiOutputContent = aiOutputContent
        self.safetyPresentation = safetyPresentation
        self.isNew = isNew
        self.sendFailed = sendFailed
        self.isStreaming = isStreaming
        self.isStarterPrompt = isStarterPrompt
        self.promptVersion = promptVersion
        self.modelIdentifier = modelIdentifier
        self.zone = zone
        self.wasDegraded = wasDegraded
    }

    /// A reply the assistant actually generated.
    ///
    /// Not the same as `!isFromUser`, which was a safe reading of the
    /// transcript only while there were exactly two kinds of message. A
    /// starter prompt is neither the person's turn nor the assistant's, so
    /// anything that means "an answer" — regenerate, feedback, speak, the
    /// summarisable-conversation count — must ask this instead.
    public var isAssistantReply: Bool { !isFromUser && !isStarterPrompt }

    /// The question a suggestion card asked, shown in the transcript.
    /// Never a user turn — see `isStarterPrompt`.
    public static func starterPrompt(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(),
        isNew: Bool = true
    ) -> ChatMessage {
        ChatMessage(
            id: id,
            content: text,
            isFromUser: false,
            timestamp: timestamp,
            isNew: isNew,
            isStarterPrompt: true
        )
    }

    // Convenience initializer for AI messages with structured content
    public static func aiMessage(
        id: UUID = UUID(),
        heading1: String? = nil,
        heading2: String? = nil,
        body: String,
        citations: [JournalCitation]? = nil,
        facts: [InsightFact]? = nil,
        safetyPresentation: ChatSafetyPresentation = .none,
        timestamp: Date = Date(),
        isNew: Bool = false,
        isStreaming: Bool = false,
        promptVersion: String? = nil,
        modelIdentifier: String? = nil,
        zone: String? = nil,
        wasDegraded: Bool? = nil
    ) -> ChatMessage {
        let outputContent = AIOutputContent(
            heading1: heading1,
            heading2: heading2,
            body: body,
            citations: citations,
            facts: facts
        )
        return ChatMessage(
            id: id,
            content: body, // Keep content for backwards compatibility
            isFromUser: false,
            timestamp: timestamp,
            citations: citations,
            aiOutputContent: outputContent,
            safetyPresentation: safetyPresentation,
            isNew: isNew,
            isStreaming: isStreaming,
            promptVersion: promptVersion,
            modelIdentifier: modelIdentifier,
            zone: zone,
            wasDegraded: wasDegraded
        )
    }

    /// Citations for the sheet: stored sources first, then fact supporting IDs
    /// so a statistic tap still opens when only Swift `n` was persisted.
    var citationSheetItems: [JournalCitation] {
        if let citations, !citations.isEmpty { return citations }
        if let aiCitations = aiOutputContent?.citations, !aiCitations.isEmpty {
            return aiCitations
        }
        var seen = Set<UUID>()
        var result: [JournalCitation] = []
        for fact in aiOutputContent?.facts ?? [] {
            for entryId in fact.supportingEntryIDs where seen.insert(entryId).inserted {
                result.append(JournalCitation(
                    entryId: entryId,
                    entryTitle: fact.label,
                    entryDate: fact.window.start,
                    excerpt: fact.value
                ))
            }
        }
        return result
    }
}
