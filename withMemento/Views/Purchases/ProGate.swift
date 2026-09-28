//
//  ProGate.swift
//  withMemento
//
//  Spec 021 R4: wraps a paid surface (Weekly, Patterns, Ask). Unentitled users
//  on an Apple Intelligence device see the surface dimmed under a calm offer
//  card; entitled users and ineligible devices see the surface untouched
//  (the latter render their own "unavailable" state — never a paywall, R2).
//
//  The offer is opened by the user, never pushed at them on entry: the
//  surface stays quiet, in keeping with "never nag" (spec 017 R3).
//

import SwiftUI

extension View {
    /// Gate this paid surface behind Memento Pro. `feature` names it in the
    /// offer card ("Weekly reflections").
    func proGated(_ feature: String) -> some View {
        modifier(ProGateModifier(feature: feature))
    }
}

private struct ProGateModifier: ViewModifier {
    let feature: String

    @ObservedObject private var store = EntitlementStore.shared
    @State private var availability: IntelligenceAvailability?
    @State private var showPaywall = false

    private var decision: ProAccessDecision {
        // Until availability resolves, only an entitled user is let through;
        // everyone else sees the surface without the card for that instant.
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
        let locked = decision == .showPaywall
        content
            .blur(radius: locked ? 6 : 0)
            .allowsHitTesting(!locked)
            .accessibilityHidden(locked)
            .overlay {
                if locked {
                    ProOfferCard(feature: feature) { showPaywall = true }
                        .padding(Spacing.lg)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: locked)
            // Evaluated when the surface appears, never cached at launch (R2).
            .task { availability = await FoundationModelsIntelligenceService.shared.availability() }
            .sheet(isPresented: $showPaywall) {
                MementoProPaywall()
            }
    }
}

private struct ProOfferCard: View {
    let feature: String
    let onUnlock: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 28)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text("\(feature) is part of Memento Pro")
                    .font(type.h5)
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                Text("Writing, search, and export stay free forever. Pro adds reflections, patterns, and Ask.")
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Unlock Memento Pro", action: onUnlock)
                .accessibilityIdentifier("proGate.unlock")
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 420)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(theme.mutedForeground.opacity(0.2))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("proGate.card")
    }
}
