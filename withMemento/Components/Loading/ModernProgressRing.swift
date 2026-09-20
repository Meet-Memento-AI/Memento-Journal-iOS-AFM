//
//  ModernProgressRing.swift
//  MeetMemento
//
//  Shared animated progress ring component
//

import SwiftUI

struct ModernProgressRing: View {
    @Environment(\.theme) private var theme
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // Subtle background ring
            Circle()
                .stroke(theme.border.opacity(0.3), lineWidth: 2.5)

            // Animated gradient arc
            Circle()
                .trim(from: 0, to: 0.65)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: theme.primary, location: 0.0),
                            .init(color: theme.accent, location: 0.5),
                            .init(color: theme.primary.opacity(0.3), location: 1.0)
                        ]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(rotation))
                .animation(
                    .linear(duration: 1.5)
                    .repeatForever(autoreverses: false),
                    value: rotation
                )
        }
        .onAppear {
            rotation = 360
        }
    }
}

#Preview("Progress Ring") {
    ModernProgressRing()
        .frame(width: 48, height: 48)
        .useTheme()
}
