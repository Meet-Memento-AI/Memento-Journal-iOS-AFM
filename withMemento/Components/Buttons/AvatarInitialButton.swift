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
    var size: CGFloat = AppHeaderMetrics.controlSize
    var fontSize: CGFloat? = nil  // nil = derived from size
    var enableHaptic: Bool = false
    var accessibilityLabel: String = "Menu"
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme

    private var resolvedFont: Font {
        fontSize.map { .system(size: $0, weight: .semibold) } ?? .headline
    }

    var body: some View {
        Button(action: {
            if enableHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onTap?()
        }) {
            ZStack {
                if let initial, !initial.isEmpty {
                    Text(initial.uppercased())
                        .font(resolvedFont)
                        .foregroundStyle(theme.foreground)
                } else {
                    Image(systemName: "person.fill")
                        .font(AppHeaderMetrics.controlSymbolFont)
                        .foregroundStyle(theme.foreground)
                }
            }
            .mementoGlassButtonChrome(shape: .circle, minLength: size)
        }
        // `.plain`, not IconButtonPressStyle: the glass is `.interactive()`, which
        // supplies its own press scale/bounce. Keeping the custom 0.92 scale on
        // top compounds two press animations. `.plain` rather than the default
        // style so the button doesn't tint the initial glyph.
        .buttonStyle(.plain)
        // Without this, SwiftUI promotes the inner glyph to be the accessibility
        // element: the tree reported this control as a 13×14pt `person.fill`
        // image, flagged NOT hittable, instead of the 48pt circle. The
        // destructive-flow UI test taps `app.buttons["Menu"]`, so that mismatch
        // fails the test even though a finger hits the button fine.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

}

// MARK: - Previews

#Preview("With Initial") {
    ZStack {
        Color.white.ignoresSafeArea()

        HStack(spacing: 16) {
            AvatarInitialButton(initial: "S", onTap: { AppLogger.log("Menu") })
            AvatarInitialButton(initial: "S", size: 96, onTap: { AppLogger.log("Menu") })
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
