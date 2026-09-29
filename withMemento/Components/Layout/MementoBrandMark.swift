//
//  MementoBrandMark.swift
//  withMemento
//
//  The mark in the app icon's own colours: each shape (body and sparkle) runs
//  the full `BrandColors.markLeading` → `markTrailing` ramp across its own
//  width, as in `AppIcon-iOS.png`. Decorative, so hidden from VoiceOver.
//

import SwiftUI

struct MementoBrandMark: View {
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            WelcomeMarkBodyShape()
                .fill(ramp(fromX: 12, toX: 60))
            WelcomeMarkSparkleShape()
                .fill(ramp(fromX: 25, toX: 47))
        }
        .frame(width: size, height: size) // icon-size: brand mark, not user text
        .accessibilityHidden(true)
    }

    /// The shapes live in a 72pt viewBox. The gradient spans each shape's own
    /// horizontal extent, not the whole frame.
    private func ramp(fromX: CGFloat, toX: CGFloat) -> LinearGradient {
        LinearGradient(
            colors: [BrandColors.markLeading, BrandColors.markTrailing],
            startPoint: UnitPoint(x: fromX / 72, y: 0.5),
            endPoint: UnitPoint(x: toX / 72, y: 0.5)
        )
    }
}

#Preview("Light") {
    MementoBrandMark(size: 144)
        .padding()
        .useTheme()
}

#Preview("Dark") {
    MementoBrandMark(size: 144)
        .padding()
        .background(Theme.dark.background)
        .useTheme()
        .preferredColorScheme(.dark)
}
