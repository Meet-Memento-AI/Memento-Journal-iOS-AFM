//
//  SafetyRouter.swift
//  MeetMemento
//
//  Maps SafetyCategory → SafetyAction and authored refuse / crisis copy (spec 026).
//

import Foundation

enum SafetyRouter {

    static func action(for category: SafetyCategory) -> SafetyAction {
        switch category {
        case .selfHarmCrisis:
            return .showCrisisCard
        case .csam, .terrorismMassViolence, .violenceOthers, .hateHarassment, .jailbreak:
            return .hardRefuse
        case .regulatedAdvice:
            return .continueConstrained
        case .clear:
            return .continue
        }
    }

    static func decide(_ text: String) -> SafetyDecision {
        SafetyClassifier.classify(text)
    }

    /// Authored hard-refuse body — never model-generated.
    static func refuseMessage(for category: SafetyCategory) -> String {
        switch category {
        case .jailbreak:
            return "I can’t change how I work or drop my boundaries. I’m here as a journaling companion — we can keep reflecting on what you’ve written."
        case .csam, .terrorismMassViolence, .violenceOthers, .hateHarassment:
            return "I can’t help with that. I’m here to reflect on your journaling, not to assist with harm."
        default:
            return "I can’t help with that. I’m here to reflect on your journaling."
        }
    }

    /// Brief authored acknowledgment shown with the crisis card (not counseling).
    static let crisisAcknowledgment =
        "I’m concerned about what you’re sharing. Please reach out for real support — I’m a journaling companion, not a crisis service."

    /// Stance overlay prepended when generation continues under constraints.
    static let constrainedStanceLine =
        "[Safety: no advice — do not diagnose; do not give medical, legal, or financial instructions; do not say \"you should\"; reflect only, then one open question]"
}
