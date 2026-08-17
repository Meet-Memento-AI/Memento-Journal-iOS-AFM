//
//  NewEntryFAB.swift
//  MeetMemento
//
//  Floating Action Button for creating new journal entries.
//  Plain, untinted Liquid Glass — no `.glassProminent`, no brand fill — so it
//  reads as chrome over whatever it floats above and inverts with the theme.
//

import SwiftUI

public struct NewEntryFAB: View {
    let action: () -> Void
    var size: CGFloat = 64
    var enableHaptic: Bool = true

    @Environment(\.theme) private var theme

    public init(size: CGFloat = 64, enableHaptic: Bool = true, action: @escaping () -> Void) {
        self.size = size
        self.enableHaptic = enableHaptic
        self.action = action
    }

    public var body: some View {
        Button {
            if enableHaptic {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            action()
        } label: {
            // Glass on the view CONTAINING the glyph, not a layer behind it:
            // only content composited inside the effect receives the system's
            // vibrancy treatment, which adapts the glyph to whatever is being
            // refracted. As a `.background(...)` layer it keeps its literal
            // token colour and washes out — the note on `AvatarInitialButton`.
            //
            // No `.tint()` and no fill underneath: an opaque fill beneath glass
            // renders it as a flat panel. `theme.foreground` gives a dark glyph
            // in light mode and a light one in dark.
            Image(systemName: "square.and.pencil")
                .font(.system(size: size * 0.4, weight: .bold)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(FABPressStyle())
        .accessibilityLabel("New Journal Entry")
        .accessibilityIdentifier("journal.newEntryFAB")
    }
}

private struct FABPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Positioned Wrapper

/// Positions the FAB in the bottom-right corner of whatever it overlays.
///
/// It used to take a `swipeProgress` scalar and fade/scale/slide itself out as
/// the user paged toward Chat, because it was a *sibling* of the pager and would
/// otherwise have hovered over both screens. It now lives inside the Journal
/// page and simply travels with it, so the whole animation — and the plumbing
/// that computed the scalar — is gone.
///
/// Edge insets match the Chat/Journal footer: `windowBottom + 16` above
/// the physical bottom (the scaffold owns the home-indicator pad).
public struct PositionedNewEntryFAB: View {
    public static let fabSize: CGFloat = AppHeaderMetrics.footerButtonSize
    public static let edgeInset: CGFloat = AppHeaderMetrics.contentGap
    /// Scroll-content clearance: FAB + 16pt edge + home indicator + 8pt air.
    public static var scrollClearance: CGFloat {
        fabSize + edgeInset + AppHeaderMetrics.windowBottom + 8
    }

    let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                NewEntryFAB(size: Self.fabSize, action: action)
                    .padding(.trailing, Self.edgeInset)
                    .padding(.bottom, Self.edgeInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Light") {
    ZStack {
        LinearGradient(colors: [.blue.opacity(0.3), .purple.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
        VStack { Spacer(); HStack { Spacer(); NewEntryFAB { }.padding(20) } }
    }
    .useTheme().useTypography()
}

#Preview("Dark") {
    ZStack {
        GrayScale.gray900.ignoresSafeArea()
        VStack { Spacer(); HStack { Spacer(); NewEntryFAB { }.padding(20) } }
    }
    .useTheme().useTypography().preferredColorScheme(.dark)
}
