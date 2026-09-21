//
//  ResponsePolicy.swift
//  MeetMemento
//
//  How to answer, chosen from the question shape before generation.
//  Venting reflects. A task gets an answer. A goodbye does not ask another question.
//

import Foundation

enum ResponsePolicy: String, Sendable, Equatable {
    case answer
    case list
    case reflect
    case acknowledge
    case retract
    case abstain
}

enum ResponsePolicyResolver {

    static func policy(shape: QuestionShape, evidence: EvidenceState = .matched) -> ResponsePolicy {
        switch shape {
        case .advice, .list:
            return .list
        case .venting:
            return .reflect
        case .goodbye:
            return .acknowledge
        case .correction, .interpretationCut:
            return .retract
        case .inventory, .temporal, .entity, .specific:
            return evidence == .ambient ? .abstain : .answer
        }
    }

    /// `rule.noOpen` stays quiet on task policies and on an empty statistic body.
    static func openRequired(policy: ResponsePolicy, bodyIsEmpty: Bool) -> Bool {
        if bodyIsEmpty { return false }
        switch policy {
        case .list, .answer, .acknowledge, .retract:
            return false
        case .reflect, .abstain:
            return true
        }
    }
}
