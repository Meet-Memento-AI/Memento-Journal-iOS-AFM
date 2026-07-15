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

    @Environment(\.theme) private var theme

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
                        .font(.system(size: resolvedFontSize, weight: .semibold))
                        .foregroundStyle(PrimaryScale.primary600)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: resolvedFontSize, weight: .medium))
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
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // iOS 26: Pure liquid glass with shadow
            Circle()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Circle())
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        } else {
            fallbackGlassBackground
        }
        #else
        fallbackGlassBackground
        #endif
    }

    @ViewBuilder
    private var fallbackGlassBackground: some View {
        // iOS 18+: Ultra thin material fallback with shadow
        Circle()
            .fill(.thinMaterial)
            .overlay(
                Circle()
                    .strokeBorder(theme.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
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
