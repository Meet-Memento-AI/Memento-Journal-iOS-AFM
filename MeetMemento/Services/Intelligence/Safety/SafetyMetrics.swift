//
//  SafetyMetrics.swift
//  MeetMemento
//
//  Privacy-preserving local counters — category/action enums only, never plaintext.
//

import Foundation

enum SafetyMetrics {
    private static let defaults = UserDefaults.standard
    private static let prefix = "memento.safety.route."

    static func record(_ decision: SafetyDecision) {
        let key = prefix + decision.action.rawValue + "." + decision.category.rawValue
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    static func recordAFMGuardrailRefusal() {
        let key = prefix + "afm_guardrail_refusal"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
    }

    static func count(action: SafetyAction, category: SafetyCategory) -> Int {
        defaults.integer(forKey: prefix + action.rawValue + "." + category.rawValue)
    }
}
