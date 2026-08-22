//
//  LoadingStatus.swift
//  MeetMemento
//
//  Instant loading-row copy from TurnClassifier. No model call — the same
//  classify used on the send path, mapped to a short process phrase.
//  Retrieval copy only when RetrievalPolicy will actually run a search.
//

import Foundation

enum LoadingStatus {
    static let fallback = "Memento is thinking…"
    static let sessionLoad = "Opening this conversation…"

    static func phrase(for turn: TurnType, history: [ChatTurn] = []) -> String {
        switch RetrievalPolicy.mode(for: turn, history: history) {
        case .none:
            return fallback
        case .reusePrevious, .currentOnly, .currentWeighted:
            return "Reviewing your past entries…"
        }
    }

    /// Second line after ~1s, only when retrieval actually runs.
    static func followUpPhrase(for turn: TurnType, history: [ChatTurn] = []) -> String? {
        switch RetrievalPolicy.mode(for: turn, history: history) {
        case .none:
            return nil
        case .reusePrevious, .currentOnly, .currentWeighted:
            return "Finding what fits…"
        }
    }
}
