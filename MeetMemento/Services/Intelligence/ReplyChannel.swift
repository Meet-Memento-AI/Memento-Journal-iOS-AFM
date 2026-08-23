//
//  ReplyChannel.swift
//  MeetMemento
//
//  Spec 039: the only mapping from TurnType (+ photos) to a generation
//  recipe. Rank 0 is cheapest. Skipping a rank (ask@14 + 512 tokens on a
//  greeting) is a spec violation. No `import FoundationModels` — pure Swift.
//

import Foundation

/// Generation recipe for one Ask turn. Resolved after SafetyRouter and
/// TurnClassifier; consumed by `prepareAsk` and PromptRegistry.
enum ReplyChannel: String, Sendable, Equatable, CaseIterable {
    case phatic
    case continuer
    case meta
    case companion
    case thread
    case notebook
    case redirect

    /// Exhaustive map. Photo bump: any in-session image never resolves to
    /// phatic or continuer — bump to companion unless the text is a journal
    /// ask (notebook) or meta (meta).
    static func resolve(turn: TurnType, hasImages: Bool) -> ReplyChannel {
        let base: ReplyChannel
        switch turn {
        case .social: base = .phatic
        case .acknowledgement: base = .continuer
        case .meta: base = .meta
        case .share, .reflectiveQuestion: base = .companion
        case .followup: base = .thread
        case .journalQuery: base = .notebook
        case .offdomain: base = .redirect
        }
        guard hasImages else { return base }
        switch base {
        case .phatic, .continuer:
            return .companion
        default:
            return base
        }
    }

    /// Ranks 0–1 leave ask@14 for `chat-light@4`.
    var usesLightPrompt: Bool {
        switch self {
        case .phatic, .continuer: return true
        default: return false
        }
    }

    /// L1 "About this person" is omitted on phatic, continuer, and redirect.
    var omitsLens: Bool {
        switch self {
        case .phatic, .continuer, .redirect: return true
        default: return false
        }
    }

    /// Default RAG path is notebook only. Thread may retrieve when the
    /// follow-up is journal-anchored (`reusePrevious`).
    var allowsRetrieval: Bool {
        switch self {
        case .notebook, .thread: return true
        default: return false
        }
    }

    /// Spec 039 R1 token caps. Notebook keeps 512; thread uses 512 only when
    /// RAG actually ran. Light caps are one spoken sentence plus a question.
    func maximumResponseTokens(retrievalRan: Bool) -> Int {
        switch self {
        case .phatic: return 80
        case .continuer: return 64
        case .meta, .companion: return 128
        case .thread: return retrievalRan ? 512 : 128
        case .notebook: return 512
        case .redirect: return 80
        }
    }

    /// Light / companion / redirect stay warmer. Notebook and RAG thread
    /// stay grounded at 0.7.
    var temperature: Double {
        switch self {
        case .phatic, .continuer, .meta, .companion, .redirect: return 0.9
        case .thread, .notebook: return 0.7
        }
    }

    /// Thread without RAG uses the companion temperature.
    func temperature(retrievalRan: Bool) -> Double {
        if self == .thread { return retrievalRan ? 0.7 : 0.9 }
        return temperature
    }
}
