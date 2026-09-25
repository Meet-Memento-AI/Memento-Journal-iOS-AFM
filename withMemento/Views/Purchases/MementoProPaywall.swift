//
//  MementoProPaywall.swift
//  withMemento
//
//  Spec 021: presentation wrappers around RevenueCatUI. The paywall renders
//  the dashboard's *current* offering (annual first, R1) and prices straight
//  from the store — no price literal lives in this app. Its template's
//  Restore Purchases button is the one-tap cross-device path (R3).
//

import RevenueCat
import RevenueCatUI
import SwiftUI

/// The RevenueCat paywall, wired to `EntitlementStore`. Dismisses itself on a
/// successful purchase or restore.
struct MementoProPaywall: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = EntitlementStore.shared

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { info in
                store.apply(info)
                dismiss()
            }
            .onRestoreCompleted { info in
                store.apply(info)
                if store.isPro {
                    dismiss()
                } else {
                    store.lastError = "No Memento Pro purchase was found for this Apple Account."
                }
            }
            .onPurchaseFailure { error in
                store.lastError = EntitlementStore.message(for: error)
            }
            .onRestoreFailure { error in
                store.lastError = EntitlementStore.message(for: error)
            }
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
