//
//  SafetyTypes.swift
//  MeetMemento
//
//  Harm taxonomy + routing actions for the on-device Safety layer (spec 026).
//

import Foundation

/// Harm / policy categories the deterministic SafetyClassifier can emit.
enum SafetyCategory: String, Sendable, Equatable, CaseIterable, Codable {
    case csam
    case terrorismMassViolence
    case violenceOthers
    case selfHarmCrisis
    case hateHarassment
    case jailbreak
    case regulatedAdvice
    case clear

    /// Precedence rank — lower number wins (spec 026 R3).
    var precedence: Int {
        switch self {
        case .csam: return 0
        case .terrorismMassViolence: return 1
        case .violenceOthers: return 2
        case .selfHarmCrisis: return 3
        case .hateHarassment: return 4
        case .jailbreak: return 5
        case .regulatedAdvice: return 6
        case .clear: return 7
        }
    }
}

/// What the SafetyRouter does with a classified message.
enum SafetyAction: String, Sendable, Equatable, CaseIterable, Codable {
    /// Static crisis resource card; never call the model.
    case showCrisisCard
    /// Authored refuse template; never call the model; no retrieval.
    case hardRefuse
    /// Continue generation under a no-advice / no-diagnosis constraint.
    case continueConstrained
    /// Normal TurnClassifier path.
    case `continue`
}

/// Classifier output. `confidence` is reserved for future tuning (always high for lexicon hits).
struct SafetyDecision: Sendable, Equatable {
    let category: SafetyCategory
    let action: SafetyAction
    let confidence: Double

    static let clear = SafetyDecision(category: .clear, action: .continue, confidence: 1)
}

/// How an assistant chat bubble should present a Safety route (UI only).
public enum ChatSafetyPresentation: String, Sendable, Equatable, Hashable, Codable {
    case none
    case crisisResource
    case hardRefuse
    /// The model produced nothing usable for this turn (Apple's guardrail
    /// declined it). Authored copy, not an answer — so it must not carry the
    /// affordances of one. Copying, reading aloud or rating "I don't have an
    /// observation for this one." is meaningless; regenerating it is the only
    /// action that does anything, and this used to render with the full bar.
    case emptyObservation
}
