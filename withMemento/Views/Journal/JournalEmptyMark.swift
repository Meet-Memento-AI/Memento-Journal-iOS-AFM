//
//  JournalEmptyMark.swift
//  withMemento
//
//  Centered empty-journal glyph. Figma 791:2980 — the rebrand mark at 144pt
//  with a very light inner shadow, not Liquid Glass (this is content).
//

import SwiftUI

struct JournalEmptyMark: View {
    /// Figma AppIcon node is 144×144.
    var size: CGFloat = 144

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            WelcomeMarkBodyShape()
                .fill(fillStyle)
            WelcomeMarkSparkleShape()
                .fill(fillStyle)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Light gray on the journal canvas; a low-opacity white in dark so the
    /// mark still reads on black. Inner shadow is Figma's inset treatment.
    private var fillStyle: some ShapeStyle {
        fillColor.shadow(.inner(color: innerShadowColor, radius: 3.5, y: 1))
    }

    private var fillColor: Color {
        colorScheme == .dark
            ? theme.foreground.opacity(0.08)
            : GrayScale.gray200
    }

    private var innerShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.45) // theme-exempt: inner shadow
            : Color.black.opacity(0.07) // theme-exempt: inner shadow
    }
}

#Preview("Light") {
    ZStack {
        GrayScale.gray50.ignoresSafeArea()
        JournalEmptyMark()
    }
    .useTheme()
}

#Preview("Dark") {
    ZStack {
        Theme.dark.secondaryBackground.ignoresSafeArea()
        JournalEmptyMark()
    }
    .useTheme()
    .preferredColorScheme(.dark)
}
