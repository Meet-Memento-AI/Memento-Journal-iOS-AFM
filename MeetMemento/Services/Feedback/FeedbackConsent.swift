//
//  FeedbackConsent.swift
//  MeetMemento
//
//  Spec 042 verification consent. Thumbs need the Settings toggle
//  (metadata only). Submitting a Report is per-event consent and always
//  sends metadata plus the question and answer.
//

import Foundation

enum FeedbackConsentTier: String, Equatable {
    case none
    case metadata
    case metadataAndText
}

enum FeedbackConsent {
    /// Settings switch for ratings. Off by default. Reports do not read this.
    static var shareWithDeveloper: Bool {
        PreferencesService.shared.shareFeedbackWithDeveloper
    }

    static func tier(
        shareWithDeveloper: Bool,
        source: AnswerFeedbackSource,
        includeTextForReview: Bool
    ) -> FeedbackConsentTier {
        if source == .report {
            return .metadataAndText
        }
        guard shareWithDeveloper else { return .none }
        return .metadata
    }
}
