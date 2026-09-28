//
//  ProDecision.swift
//  withMemento
//
//  Spec 021 R2/R4: one place that turns entitlement × device eligibility into
//  a `ProAccessDecision` for a view. Used by `.proGated(_:)` (Weekly,
//  Patterns) and by the chat, which shows its free variant rather than a lock
//  (DEC-013: a free user opening Ask gets the free chat).
//
//  Evaluated when the surface appears, never cached at launch (R2).
//

import SwiftUI

/// Which chat the person gets.
enum ChatTier: Equatable {
    /// Full chat: whole-journal Ask, history, summaries. Also used on devices
    /// without Apple Intelligence, where the chat shows its own unavailable
    /// state and no purchase UI ever appears (DEC-001).
    case pro
    /// Free chat: the latest entry plus this conversation, a daily message
    /// limit, and an Upgrade button (spec 021 R4 `REQ-MON-006`).
    case free

    init(_ decision: ProAccessDecision) {
        self = decision == .showPaywall ? .free : .pro
    }
}

extension ProAccess {
    #if DEBUG
    /// `-ForceFreeTier` (DEBUG builds only): show the free tier while
    /// RevenueCat is switched off, for design review and FreeChatUITests.
    /// Not paired with `-UITesting`, which forces onboarding and so would
    /// never reach the chat; the chat UI tests launch without it.
    static var forcesFreeTier: Bool {
        ProcessInfo.processInfo.arguments.contains("-ForceFreeTier")
    }
    #endif
}

extension View {
    /// Keeps `decision` in step with entitlement and device eligibility.
    func resolveProDecision(_ decision: Binding<ProAccessDecision>) -> some View {
        modifier(ProDecisionModifier(decision: decision))
    }
}

private struct ProDecisionModifier: ViewModifier {
    @Binding var decision: ProAccessDecision

    @ObservedObject private var store = EntitlementStore.shared
    @State private var availability: IntelligenceAvailability?

    private var resolved: ProAccessDecision {
        #if DEBUG
        if ProAccess.forcesFreeTier { return .showPaywall }
        #endif
        // Until availability resolves, only an entitled user is let through;
        // everyone else sees the surface without an offer for that instant.
        guard let availability else {
            return store.isPro || !store.isConfigured ? .unlocked : .unavailableDevice
        }
        return ProAccess.decide(
            isPro: store.isPro,
            availability: availability,
            purchasesConfigured: store.isConfigured
        )
    }

    func body(content: Content) -> some View {
        content
            .task { availability = await FoundationModelsIntelligenceService.shared.availability() }
            .onChange(of: resolved, initial: true) { _, new in
                decision = new
            }
    }
}
