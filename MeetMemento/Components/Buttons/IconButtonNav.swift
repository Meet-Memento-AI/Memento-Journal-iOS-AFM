//
//  IconButtonNav.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/13/26.
//

import SwiftUI

/// A circular navigation button with Liquid Glass.
/// Matches `HeaderIconButton` / `AvatarInitialButton`: glass on the view that
/// contains the glyph, `.regular.interactive()`, no opaque fill underneath.
struct IconButtonNav: View {
    // MARK: - Inputs
    let icon: String
    var iconSize: CGFloat = 24
    var buttonSize: CGFloat = AppHeaderMetrics.controlSize
    var foregroundColor: Color? = nil  // nil = use theme.foreground
    /// Kept for call-site compatibility. `.regular` glass already adapts to
    /// light and dark backdrops, so this no longer switches a fill.
    var useDarkBackground: Bool = false
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
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold)) // icon-size: not user text
                .foregroundStyle(foregroundColor ?? theme.foreground)
                .frame(width: buttonSize, height: buttonSize)
                // Glass on the view CONTAINING the glyph, not a layer behind it:
                // only content composited inside the effect gets vibrancy.
                // No opaque Circle fill — that would read as the old gray chip.
                .glassEffect(.regular.interactive(), in: .circle)
                // Lock layout at rest. `.interactive()` still scales the glass
                // on press; this outer frame keeps neighbours from shifting.
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Circle())
        }
        // `.plain`, not a custom press style: `.interactive()` supplies the
        // system press scale/bounce. A second scale would compound it.
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? icon)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Previews

#Preview("Light Background") {
    ZStack {
        LinearGradient(
            colors: [GrayScale.gray100, GrayScale.gray50],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 24) {
            HStack(spacing: 16) {
                IconButtonNav(
                    icon: "chevron.left",
                    onTap: { AppLogger.log("Back") }
                )

                Spacer()

                Text("Settings")
                    .font(Typography().body1Medium)

                Spacer()

                Color.clear
                    .frame(
                        width: AppHeaderMetrics.controlSize,
                        height: AppHeaderMetrics.controlSize
                    )
            }
            .padding(.horizontal, 16)

            Spacer()
        }
    }
    .useTheme()
}

#Preview("Header Buttons - Light") {
    ZStack {
        LinearGradient(
            colors: [GrayScale.gray100, GrayScale.gray50],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                IconButtonNav(
                    icon: "line.3.horizontal",
                    onTap: { AppLogger.log("Menu") }
                )

                IconButtonNav(
                    icon: "sparkles",
                    onTap: { AppLogger.log("AI") }
                )
            }
        }
    }
    .useTheme()
}

#Preview("Header Buttons - Dark (Insights)") {
    ZStack {
        PrimaryScale.primary900
            .ignoresSafeArea()

        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                IconButtonNav(
                    icon: "line.3.horizontal",
                    foregroundColor: .white,
                    useDarkBackground: true,
                    enableHaptic: true,
                    onTap: { AppLogger.log("Menu") }
                )

                IconButtonNav(
                    icon: "sparkles",
                    foregroundColor: .white,
                    useDarkBackground: true,
                    enableHaptic: true,
                    onTap: { AppLogger.log("AI") }
                )
            }
        }
    }
    .useTheme()
}

#Preview("Various Sizes") {
    ZStack {
        LinearGradient(
            colors: [GrayScale.gray100, GrayScale.gray50],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()

        HStack(spacing: 20) {
            IconButtonNav(
                icon: "chevron.left",
                iconSize: 20,
                buttonSize: 40,
                onTap: {}
            )

            IconButtonNav(
                icon: "chevron.left",
                onTap: {}
            )

            IconButtonNav(
                icon: "chevron.left",
                iconSize: 32,
                buttonSize: 64,
                onTap: {}
            )
        }
    }
    .useTheme()
}
