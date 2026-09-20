//
//  AISparkleIcon.swift
//  MeetMemento
//
//  Purple gradient sparkle icon for AI chat input
//

import SwiftUI

struct AISparkleIcon: View {
    var size: CGFloat = 20

    private let gradientStart = BrandColors.brand
    private let gradientEnd = BrandColors.brandOnText

    var body: some View {
        ZStack {
            // Main sparkle shape
            mainSparkle
            // Small accent star
            accentStar
        }
        .frame(width: size, height: size)
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [gradientStart, gradientEnd],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var mainSparkle: some View {
        // Four-pointed star sparkle
        Path { path in
            let center = CGPoint(x: size * 0.45, y: size * 0.5)
            let horizontalRadius = size * 0.4
            let verticalRadius = size * 0.45
            let controlOffset = size * 0.08

            // Top point
            path.move(to: CGPoint(x: center.x, y: center.y - verticalRadius))

            // Top-right curve to right point
            path.addQuadCurve(
                to: CGPoint(x: center.x + horizontalRadius, y: center.y),
                control: CGPoint(x: center.x + controlOffset, y: center.y - controlOffset)
            )

            // Right-bottom curve to bottom point
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y + verticalRadius),
                control: CGPoint(x: center.x + controlOffset, y: center.y + controlOffset)
            )

            // Bottom-left curve to left point
            path.addQuadCurve(
                to: CGPoint(x: center.x - horizontalRadius, y: center.y),
                control: CGPoint(x: center.x - controlOffset, y: center.y + controlOffset)
            )

            // Left-top curve back to top
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y - verticalRadius),
                control: CGPoint(x: center.x - controlOffset, y: center.y - controlOffset)
            )

            path.closeSubpath()
        }
        .fill(gradient)
    }

    private var accentStar: some View {
        // Small four-pointed star in top-right
        Path { path in
            let center = CGPoint(x: size * 0.82, y: size * 0.18)
            let radius = size * 0.12
            let controlOffset = size * 0.03

            // Top point
            path.move(to: CGPoint(x: center.x, y: center.y - radius))

            // Top-right curve to right point
            path.addQuadCurve(
                to: CGPoint(x: center.x + radius, y: center.y),
                control: CGPoint(x: center.x + controlOffset, y: center.y - controlOffset)
            )

            // Right-bottom curve to bottom point
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y + radius),
                control: CGPoint(x: center.x + controlOffset, y: center.y + controlOffset)
            )

            // Bottom-left curve to left point
            path.addQuadCurve(
                to: CGPoint(x: center.x - radius, y: center.y),
                control: CGPoint(x: center.x - controlOffset, y: center.y + controlOffset)
            )

            // Left-top curve back to top
            path.addQuadCurve(
                to: CGPoint(x: center.x, y: center.y - radius),
                control: CGPoint(x: center.x - controlOffset, y: center.y - controlOffset)
            )

            path.closeSubpath()
        }
        .fill(gradient)
    }
}

// MARK: - Previews

#Preview("AI Sparkle Icon") {
    VStack(spacing: 20) {
        AISparkleIcon(size: 16)
        AISparkleIcon(size: 20)
        AISparkleIcon(size: 32)
        AISparkleIcon(size: 48)
    }
    .padding()
    .background(Color.white)
}

#Preview("AI Sparkle Icon - Dark") {
    VStack(spacing: 20) {
        AISparkleIcon(size: 20)
        AISparkleIcon(size: 32)
    }
    .padding()
    .background(Color.black)
}
