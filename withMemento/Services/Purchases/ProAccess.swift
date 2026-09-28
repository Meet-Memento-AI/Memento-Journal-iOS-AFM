//
//  ProAccess.swift
//  withMemento
//
//  Spec 021 R2/R4: the one central gate for paid surfaces (Weekly reflections,
//  Patterns, Ask, Personal Voice). Entitlement × device eligibility — never
//  quota: a paid user who hits Apple's PCC quota is not a paywall moment.
//
//  Free forever (capture, transcription, timeline, search, export) must never
//  call this. Export in particular has no dependency on this module.
//

import Foundation

enum ProAccessDecision: Equatable {
    /// Entitled — show the feature.
    case unlocked
    /// Not entitled on a device that can run the feature — offer Memento Pro.
    case showPaywall
    /// No Apple Intelligence on this hardware. The paywall is structurally
    /// unreachable here (R2): selling AI to a device that can't generate it is
    /// a refund and a review rejection. The surface shows its own
    /// "unavailable" state instead.
    case unavailableDevice
}

enum ProAccess {
    static func decide(
        isPro: Bool,
        availability: IntelligenceAvailability,
        purchasesConfigured: Bool = true
    ) -> ProAccessDecision {
        if isPro { return .unlocked }
        // No SDK (missing key, tests): nothing can be sold, so nothing is held
        // back. Fails open — a missing Release key is loud in the logs.
        if !purchasesConfigured { return .unlocked }
        if case .unavailable(.deviceNotEligible) = availability { return .unavailableDevice }
        // Model still downloading or Apple Intelligence switched off: the
        // device can run it, so the purchase is honest.
        return .showPaywall
    }
}
