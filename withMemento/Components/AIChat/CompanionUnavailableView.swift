//
//  CompanionUnavailableView.swift
//  withMemento
//
//  Chat's pre-send state when the on-device model can't answer (device not
//  eligible, model still downloading). Distinct from AI-off in Settings: there
//  is nothing to toggle, and the journal keeps working.
//

import SwiftUI

struct CompanionUnavailableView: View {
    let reason: IntelligenceUnavailableReason
    let onCheckAgain: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 56)) // icon-size: not user text
                .foregroundStyle(theme.iconForeground.opacity(0.5))

            Text("Chat Unavailable")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text(reason.userMessage + " Your journal still works as usual.")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if reason == .modelNotReady {
                Button(action: onCheckAgain) {
                    Text("Check Again")
                        .font(type.body1Bold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(theme.primaryButtonFill)
                        .foregroundStyle(theme.primaryForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            Spacer()
        }
        .contentColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, AppHeaderMetrics.contentTopPadding)
        .accessibilityIdentifier("chat.unavailable")
    }
}

#Preview("Not eligible - Dark") {
    CompanionUnavailableView(reason: .deviceNotEligible) {}
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Model not ready - Light") {
    CompanionUnavailableView(reason: .modelNotReady) {}
        .useTheme()
        .useTypography()
}
