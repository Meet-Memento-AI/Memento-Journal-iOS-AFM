//
//  NewEntryFAB.swift
//  MeetMemento
//
//  Floating Action Button for creating new journal entries.
//  Icon-only: plain, untinted Liquid Glass — no `.glassProminent`, no brand
//  fill — so it reads as chrome over whatever it floats above and inverts
//  with the theme. Labeled (empty journal): Welcome / Summarize glass —
//  `BaseColors.black` tint, white icon and label.
//

import SwiftUI

public struct NewEntryFAB: View {
    let action: () -> Void
    var size: CGFloat = 64
    var title: String? = nil
    var enableHaptic: Bool = true

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    /// Figma 791:2889 — icon-to-label gap on the empty-state pill.
    private static let labeledGap: CGFloat = 10
    /// Figma 791:2889 — padding around icon + label.
    private static let labeledPadding: CGFloat = 16
    /// 24pt glyph; `type.h4` (20pt) is one step smaller so the label sits
    /// just under the icon's optical height.
    private static let labeledGlyphSize: CGFloat = 24
    /// 16 + 24 + 16. Floor the pill before glass so TabView overlays cannot
    /// collapse the labeled control to a zero hit box.
    static let labeledMinHeight: CGFloat = 56
    /// Half of `labeledMinHeight` — a real capsule radius for zoom source
    /// clip. `theme.radius.round` (999) can swallow the control.
    static let labeledCornerRadius: CGFloat = labeledMinHeight / 2
    /// Same black frost as Welcome Get Started and Summarize Chat: tint
    /// reads through the material instead of covering it.
    private static let labeledGlassTintOpacity: Double = 0.9

    public init(
        size: CGFloat = 64,
        title: String? = nil,
        enableHaptic: Bool = true,
        action: @escaping () -> Void
    ) {
        self.size = size
        self.title = title
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
            if let title {
                labeledLabel(title)
            } else {
                iconLabel
            }
        }
        .buttonStyle(FABPressStyle())
        .accessibilityLabel(title ?? "New Journal Entry")
        .accessibilityIdentifier("journal.newEntryFAB")
    }

    /// Glass on the view CONTAINING the glyph, not a layer behind it:
    /// only content composited inside the effect receives the system's
    /// vibrancy treatment, which adapts the glyph to whatever is being
    /// refracted. As a `.background(...)` layer it keeps its literal
    /// token colour and washes out — the note on `AvatarInitialButton`.
    ///
    /// No `.tint()` and no fill underneath: an opaque fill beneath glass
    /// renders it as a flat panel. `theme.foreground` gives a dark glyph
    /// in light mode and a light one in dark.
    private var iconLabel: some View {
        Image(systemName: "square.and.pencil")
            .font(.system(size: size * 0.4, weight: .bold)) // icon-size: not user text
            .foregroundStyle(theme.foreground)
            .frame(width: size, height: size)
            .glassEffect(.regular.interactive(), in: .circle)
    }

    /// Empty-journal CTA. Glass in a capsule, black-tinted like Welcome
    /// Get Started — white glyph and label stay readable on the frost.
    /// `.interactive()` is the same press refraction as the circular FAB.
    private func labeledLabel(_ title: String) -> some View {
        HStack(spacing: Self.labeledGap) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: Self.labeledGlyphSize, weight: .bold)) // icon-size: not user text
            Text(title)
                .font(type.h4)
                .lineLimit(1)
        }
        .foregroundStyle(BaseColors.white)
        .padding(Self.labeledPadding)
        .frame(minHeight: Self.labeledMinHeight)
        .glassEffect(
            .regular.tint(BaseColors.black.opacity(Self.labeledGlassTintOpacity)).interactive(),
            in: .capsule
        )
        .contentShape(Capsule())
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
        LinearGradient(colors: [GrayScale.gray100, GrayScale.gray50], startPoint: .topLeading, endPoint: .bottomTrailing)
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

#Preview("Labeled • Light") {
    ZStack {
        GrayScale.gray50.ignoresSafeArea()
        VStack { Spacer(); HStack { Spacer(); NewEntryFAB(title: "Write your first entry") { }.padding(20) } }
    }
    .useTheme().useTypography()
}

#Preview("Labeled • New entry") {
    ZStack {
        GrayScale.gray50.ignoresSafeArea()
        VStack { Spacer(); HStack { Spacer(); NewEntryFAB(title: "New entry") { }.padding(20) } }
    }
    .useTheme().useTypography()
}

#Preview("Labeled • Dark") {
    ZStack {
        Color(hex: "#0A0A0A").ignoresSafeArea()
        VStack { Spacer(); HStack { Spacer(); NewEntryFAB(title: "Write your first entry") { }.padding(20) } }
    }
    .useTheme().useTypography().preferredColorScheme(.dark)
}
