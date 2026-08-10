//
//  AvatarInitialButton.swift
//  MeetMemento
//

import SwiftUI

/// A circular button showing the user's first-name initial on the app's
/// default liquid-glass background. Falls back to a person glyph when no
/// initial is available yet.
struct AvatarInitialButton: View {
    // MARK: - Inputs
    let initial: String?
    var size: CGFloat = 44
    var fontSize: CGFloat? = nil  // nil = derived from size
    var enableHaptic: Bool = false
    var accessibilityLabel: String = "Menu"
    var onTap: (() -> Void)?

    private var resolvedFontSize: CGFloat {
        fontSize ?? size * 0.4
    }

    var body: some View {
        Button(action: {
            if enableHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onTap?()
        }) {
            ZStack {
                glassBackground

                if let initial, !initial.isEmpty {
                    Text(initial.uppercased())
                        .font(.system(size: resolvedFontSize, weight: .semibold)) // icon-size: not user text (avatar initial glyph scales with button size)
                        .foregroundStyle(PrimaryScale.primary600)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: resolvedFontSize, weight: .medium)) // icon-size: not user text
                        .foregroundStyle(PrimaryScale.primary600)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(IconButtonPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Glass Background

    @ViewBuilder
    private var glassBackground: some View {
        // Liquid Glass removed — flat #fafafa surface.
        Circle()
            .fill(theme.cardBackground)
    }
}

// MARK: - Previews

#Preview("With Initial") {
    ZStack {
        Color.white.ignoresSafeArea()

        HStack(spacing: 16) {
            AvatarInitialButton(initial: "S", onTap: { AppLogger.log("Menu") })
            AvatarInitialButton(initial: "S", size: 32, onTap: { AppLogger.log("Menu") })
        }
    }
    .useTheme()
}

#Preview("Fallback (No Name)") {
    ZStack {
        Color.white.ignoresSafeArea()

        AvatarInitialButton(initial: nil, onTap: { AppLogger.log("Menu") })
    }
    .useTheme()
}
