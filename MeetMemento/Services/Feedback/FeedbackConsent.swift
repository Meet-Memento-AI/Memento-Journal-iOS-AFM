//
//  FeedbackConsent.swift
//  MeetMemento
//
//  Spec 042 verification-only consent. Two tiers: metadata (default when the
//  Settings toggle is on) and metadata-plus-text (Report + explicit include).
//

import Foundation

enum FeedbackConsentTier: String, Equatable {
    case none
    case metadata
    case metadataAndText
}

enum FeedbackConsent {
    /// Settings master switch. Off by default — nothing is queued or sent.
    static var shareWithDeveloper: Bool {
        PreferencesService.shared.shareFeedbackWithDeveloper
    }

    static func tier(
        shareWithDeveloper: Bool,
        source: AnswerFeedbackSource,
        includeTextForReview: Bool
    ) -> FeedbackConsentTier {
        guard shareWithDeveloper else { return .none }
        if source == .report && includeTextForReview {
            return .metadataAndText
        }
        return .metadata
    }
}
