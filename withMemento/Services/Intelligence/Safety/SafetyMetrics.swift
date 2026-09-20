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
        defaults.set(defaults.integer(forKey: afmRefusalKey) + 1, forKey: afmRefusalKey)
    }

    /// A run of refusals long enough to be an outage rather than a content
    /// decision. Counted separately from `recordAFMGuardrailRefusal` so the
    /// safety metric is not poisoned by failures that have nothing to do with
    /// safety — the two answer different questions ("how often do we refuse?"
    /// vs. "how often is the model simply broken?").
    static func recordAFMRefusalOutage() {
        defaults.set(defaults.integer(forKey: afmOutageKey) + 1, forKey: afmOutageKey)
    }

    static var afmGuardrailRefusalCount: Int { defaults.integer(forKey: afmRefusalKey) }

    static var afmRefusalOutageCount: Int { defaults.integer(forKey: afmOutageKey) }

    private static let afmRefusalKey = prefix + "afm_guardrail_refusal"
    private static let afmOutageKey = prefix + "afm_refusal_outage"

    static func count(action: SafetyAction, category: SafetyCategory) -> Int {
        defaults.integer(forKey: prefix + action.rawValue + "." + category.rawValue)
    }
}
