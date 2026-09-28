//
//  MementoProPaywall.swift
//  withMemento
//
//  Spec 021: how the paywall is presented. The screen itself is the app's own
//  `PaywallView` over RevenueCat's *current* offering (annual first, R1,
//  prices only from the store). Restore sits in its pinned footer, the
//  one-tap cross-device path (R3). RevenueCatUI is kept only for the
//  Customer Center below.
//

import RevenueCat
import RevenueCatUI
import SwiftUI

/// The Memento Pro paywall sheet, wired to `EntitlementStore`. `PaywallView`
/// dismisses itself once Pro is active; failures surface here as one alert.
struct MementoProPaywall: View {
    /// What opened it (spec 021 R9). Settings when nothing more specific.
    var trigger: PaywallTrigger = .settings
    /// Nil uses the live store; the DEBUG harness passes preview data.
    var model: PaywallModel?

    @ObservedObject private var store = EntitlementStore.shared

    var body: some View {
        PaywallView(trigger: trigger, model: model)
            .mementoSheetPresentation()
            .alert(
                "Memento Pro",
                isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { if !$0 { store.lastError = nil } }
                )
            ) {
                Button("OK") { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
    }
}

/// RevenueCat Customer Center: plan details, cancel / change plan, refunds,
/// and restore — for people who already have Memento Pro.
struct MementoProCustomerCenter: View {
    @ObservedObject private var store = EntitlementStore.shared

    var body: some View {
        CustomerCenterView()
            .onCustomerCenterRestoreCompleted { info in
                store.apply(info)
            }
    }
}
