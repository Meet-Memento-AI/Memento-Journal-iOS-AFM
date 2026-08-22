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
                if let initial, !initial.isEmpty {
                    Text(initial.uppercased())
                        .font(.system(size: resolvedFontSize, weight: .semibold)) // icon-size: not user text (avatar initial glyph scales with button size)
                        .foregroundStyle(theme.foreground)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: resolvedFontSize, weight: .medium)) // icon-size: not user text
                        .foregroundStyle(theme.foreground)
                }
            }
            .frame(width: size, height: size)
            // Glass goes on the view that CONTAINS the glyph, not on a sibling
            // layer behind it. Only content composited inside the glass effect
            // receives the system's vibrancy treatment — which adjusts colour,
            // brightness and saturation for legibility against whatever the
            // glass is refracting. As a separate `.background(...)` layer the
            // glyph kept its literal token colour and washed out.
            .glassEffect(.regular.interactive(), in: .circle)
            // Lock layout at rest. `.interactive()` still scales the glass
            // on press; this outer frame keeps neighbours from shifting.
            .frame(width: size, height: size)
            .contentShape(Circle())
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
