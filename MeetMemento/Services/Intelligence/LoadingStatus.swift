//
//  LoadingStatus.swift
//  MeetMemento
//
//  Instant loading-row copy from TurnClassifier. No model call — the same
//  classify used on the send path, mapped to a short process phrase.
//

import Foundation

enum LoadingStatus {
    static let fallback = "Memento is thinking…"
    static let sessionLoad = "Opening this conversation…"

    static func phrase(for turn: TurnType) -> String {
        switch turn {
        case .journalQuery, .reflectiveQuestion, .share:
            return "Reviewing your past entries…"
        case .social, .acknowledgement, .meta, .offdomain, .followup:
            return fallback
        }
    }

    /// Second line after ~1s, only when retrieval actually runs.
    static func followUpPhrase(for turn: TurnType) -> String? {
        switch turn {
        case .share, .journalQuery, .reflectiveQuestion:
            return "Finding what fits…"
        case .social, .acknowledgement, .meta, .offdomain, .followup:
            return nil
        }
    }
}
