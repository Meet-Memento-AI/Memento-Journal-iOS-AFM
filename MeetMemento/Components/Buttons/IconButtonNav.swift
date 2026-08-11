//
//  IconButtonNav.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/13/26.
//

import SwiftUI

/// A circular navigation button with liquid glass styling.
/// Matches the Settings toolbar back button design.
struct IconButtonNav: View {
    // MARK: - Inputs
    let icon: String
    var iconSize: CGFloat = 20
    var buttonSize: CGFloat = 40
    var foregroundColor: Color? = nil  // nil = use theme.foreground
    var useDarkBackground: Bool = false  // Set true when on dark backgrounds (e.g., Insights)
    var enableHaptic: Bool = false
    var accessibilityLabel: String? = nil  // Custom label for screen readers
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: {
            if enableHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onTap?()
        }) {
            ZStack {
                // Liquid Glass removed — flat themed surface — cardBackground adapts to dark mode.
                Circle()
                    .fill(theme.cardBackground)

                // Icon
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(foregroundColor ?? theme.foreground)
            }
            .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(IconButtonPressStyle())
        .accessibilityLabel(accessibilityLabel ?? icon)
    }
}

// MARK: - Button Style with Press Animation

struct IconButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Light Background") {
    ZStack {
        Color.white
            .ignoresSafeArea()

        VStack(spacing: 24) {
            HStack(spacing: 16) {
                IconButtonNav(
                    icon: "chevron.left",
                    iconSize: 18,
                    buttonSize: 40,
                    onTap: { AppLogger.log("Back") }
                )

                Spacer()

                Text("Settings")
                    .font(Typography().body1Medium)

                Spacer()

                // Placeholder for symmetry
                Color.clear
                    .frame(width: 40, height: 40)
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }
    .useTheme()
}

#Preview("Header Buttons - Light") {
    ZStack {
        Color.white
            .ignoresSafeArea()

        HStack(spacing: 16) {
            IconButtonNav(
                icon: "line.3.horizontal",
                iconSize: 20,
                buttonSize: 40,
                onTap: { AppLogger.log("Menu") }
            )

            IconButtonNav(
                icon: "sparkles",
                iconSize: 22,
                buttonSize: 40,
                onTap: { AppLogger.log("AI") }
            )
        }
    }
    .useTheme()
}

#Preview("Header Buttons - Dark (Insights)") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        HStack(spacing: 16) {
            IconButtonNav(
                icon: "line.3.horizontal",
                iconSize: 20,
                buttonSize: 40,
                foregroundColor: .white,
                useDarkBackground: true,
                enableHaptic: true,
                onTap: { AppLogger.log("Menu") }
            )

            IconButtonNav(
                icon: "sparkles",
                iconSize: 22,
                buttonSize: 40,
                foregroundColor: .white,
                useDarkBackground: true,
                enableHaptic: true,
                onTap: { AppLogger.log("AI") }
            )
        }
    }
    .useTheme()
}

#Preview("Various Sizes") {
    ZStack {
        Color.white
            .ignoresSafeArea()

        HStack(spacing: 20) {
            IconButtonNav(
                icon: "chevron.left",
                iconSize: 14,
                buttonSize: 32,
                onTap: {}
            )

            IconButtonNav(
                icon: "chevron.left",
                iconSize: 16,
                buttonSize: 40,
                onTap: {}
            )

            IconButtonNav(
                icon: "chevron.left",
                iconSize: 18,
                buttonSize: 48,
                onTap: {}
            )
        }
    }
    .useTheme()
}
