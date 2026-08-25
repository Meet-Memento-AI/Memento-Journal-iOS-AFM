//
//  AnswerFeedback.swift
//  MeetMemento
//
//  On-device quality label for one assistant reply (spec 041).
//  One row per messageID; thumbs and Report mutate the same record.
//

import Foundation

/// Sentiment stored for an assistant reply. `none` means the row exists only
/// as a report (flagged for review) or after an undo.
enum AnswerFeedbackRating: String, Codable, Equatable {
    case none
    case positive
    case negative
}

/// Last writer of the row — used for analytics, not exclusive.
enum AnswerFeedbackSource: String, Codable, Equatable {
    case thumbsUp
    case thumbsDown
    case report
}

/// Why the answer was marked negative or reported. Required on the sheet.
enum AnswerFeedbackCategory: String, Codable, Equatable, CaseIterable, Identifiable {
    case wrongRecall
    case madeSomethingUp
    case didntAnswer
    case tone
    case safety
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wrongRecall: return "Wrong recall"
        case .madeSomethingUp: return "Made something up"
        case .didntAnswer: return "Didn't answer"
        case .tone: return "Tone"
        case .safety: return "Safety"
        case .other: return "Other"
        }
    }
}

/// Draft presented as a sheet from AIChatView (spec 041 R4).
struct FeedbackDraft: Identifiable, Equatable {
    enum Source: Equatable {
        case thumbsDown
        case report
    }

    var id: UUID { messageID }
    let messageID: UUID
    let source: Source
    var category: AnswerFeedbackCategory?
    var note: String
}

/// Persisted quality ticket for one assistant message.
struct AnswerFeedback: Codable, Equatable, Identifiable {
    let id: UUID
    let messageID: UUID
    var sessionID: UUID?
    var rating: AnswerFeedbackRating
    var flaggedForReview: Bool
    var category: AnswerFeedbackCategory?
    var note: String?
    var source: AnswerFeedbackSource
    var userPrompt: String
    var assistantReply: String
    var citationEntryIDs: [UUID]
    var promptVersion: String?
    var modelIdentifier: String?
    var zone: String?
    var wasDegraded: Bool?
    var safetyPresentation: String
    var appVersion: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        messageID: UUID,
        sessionID: UUID? = nil,
        rating: AnswerFeedbackRating = .none,
        flaggedForReview: Bool = false,
        category: AnswerFeedbackCategory? = nil,
        note: String? = nil,
        source: AnswerFeedbackSource,
        userPrompt: String = "",
        assistantReply: String = "",
        citationEntryIDs: [UUID] = [],
        promptVersion: String? = nil,
        modelIdentifier: String? = nil,
        zone: String? = nil,
        wasDegraded: Bool? = nil,
        safetyPresentation: String = ChatSafetyPresentation.none.rawValue,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.messageID = messageID
        self.sessionID = sessionID
        self.rating = rating
        self.flaggedForReview = flaggedForReview
        self.category = category
        self.note = note
        self.source = source
        self.userPrompt = userPrompt
        self.assistantReply = assistantReply
        self.citationEntryIDs = citationEntryIDs
        self.promptVersion = promptVersion
        self.modelIdentifier = modelIdentifier
        self.zone = zone
        self.wasDegraded = wasDegraded
        self.safetyPresentation = safetyPresentation
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
