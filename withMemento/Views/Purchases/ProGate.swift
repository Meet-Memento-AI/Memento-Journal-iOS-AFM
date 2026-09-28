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

    /// The paywall this lock opens, and whose headline the card shares.
    private var trigger: PaywallTrigger { PaywallTrigger(gate: feature) ?? .settings }

    @State private var decision: ProAccessDecision = .unavailableDevice
    @State private var showPaywall = false

    func body(content: Content) -> some View {
        let locked = decision == .showPaywall
        content
            .blur(radius: locked ? 6 : 0)
            .allowsHitTesting(!locked)
            .accessibilityHidden(locked)
            .overlay {
                if locked {
                    ProOfferCard(trigger: trigger) { showPaywall = true }
                        .padding(Spacing.lg)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: locked)
            .resolveProDecision($decision)
            .sheet(isPresented: $showPaywall) {
                MementoProPaywall(trigger: trigger)
            }
    }
}

/// The lock card speaks with the same headline and line as the paywall it
/// opens, so the card and the sheet read as one message.
private struct ProOfferCard: View {
    let trigger: PaywallTrigger
    let onUnlock: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.paywallContext) private var paywallContext

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 28)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text(trigger.title(in: paywallContext))
                    .font(type.h5)
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                Text(trigger.subtitle(in: paywallContext))
                    .font(type.body2)
                    .foregroundStyle(theme.mutedForeground)
                    .multilineTextAlignment(.center)
            }

            PrimaryButton(title: "Upgrade", action: onUnlock)
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
