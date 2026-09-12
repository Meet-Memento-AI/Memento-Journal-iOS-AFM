//
//  FeedbackEnvelope.swift
//  MeetMemento
//
//  Wire DTO for spec 042. Built from the on-device AnswerFeedback row after
//  consent redaction. Journal text is present only when the include-text flag
//  is set on an explicit Report. Citation UUIDs never travel — count only.
//

import Foundation

struct FeedbackEnvelope: Codable, Equatable {
    let id: UUID
    let messageID: UUID
    let sessionID: UUID?
    let rating: String
    let flaggedForReview: Bool
    let category: String?
    let note: String?
    let source: String
    let userPrompt: String?
    let assistantReply: String?
    let textIncluded: Bool
    let citationCount: Int
    let promptVersion: String?
    let modelIdentifier: String?
    let zone: String?
    let wasDegraded: Bool?
    let safetyPresentation: String
    let appVersion: String
    let createdAt: Date
    let updatedAt: Date
    let deviceID: UUID
    let clientEventID: UUID
    let kind: String

    static func make(
        from row: AnswerFeedback,
        deviceID: UUID,
        clientEventID: UUID = UUID(),
        includeTextForReview: Bool,
        shareWithDeveloper: Bool
    ) -> FeedbackEnvelope? {
        let tier = FeedbackConsent.tier(
            shareWithDeveloper: shareWithDeveloper,
            source: row.source,
            includeTextForReview: includeTextForReview
        )
        guard tier != .none else { return nil }

        let includeText = tier == .metadataAndText
        return FeedbackEnvelope(
            id: row.id,
            messageID: row.messageID,
            sessionID: row.sessionID,
            rating: row.rating.rawValue,
            flaggedForReview: row.flaggedForReview,
            category: row.category?.rawValue,
            note: row.note,
            source: row.source.rawValue,
            userPrompt: includeText ? row.userPrompt : nil,
            assistantReply: includeText ? row.assistantReply : nil,
            textIncluded: includeText,
            citationCount: row.citationEntryIDs.count,
            promptVersion: row.promptVersion,
            modelIdentifier: row.modelIdentifier,
            zone: row.zone,
            wasDegraded: row.wasDegraded,
            safetyPresentation: row.safetyPresentation,
            appVersion: row.appVersion,
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
            deviceID: deviceID,
            clientEventID: clientEventID,
            kind: eventKind(for: row)
        )
    }

    private static func eventKind(for row: AnswerFeedback) -> String {
        switch (row.source, row.rating) {
        case (.thumbsUp, .none): return "thumbs_up_undo"
        case (.thumbsUp, _): return "thumbs_up"
        case (.thumbsDown, .none): return "thumbs_down_undo"
        case (.thumbsDown, _): return "thumbs_down"
        case (.report, _): return "report"
        }
    }
}
