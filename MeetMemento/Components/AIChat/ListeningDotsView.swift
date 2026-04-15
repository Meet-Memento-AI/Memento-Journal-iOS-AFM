//
//  ListeningDotsView.swift
//  MeetMemento
//
//  Animated wave visualizer for voice recording listening state
//

import SwiftUI

struct ListeningDotsView: View {
    var audioLevel: Float

    @Environment(\.theme) private var theme

    private let barCount = 7
    private let barWidth: CGFloat = 4
    private let spacing: CGFloat = 6
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 64

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(theme.primary)
                    .frame(width: barWidth, height: heightForBar(index))
                    .animation(
                        .easeInOut(duration: 0.15)
                            .delay(Double(index) * 0.03),
                        value: audioLevel
                    )
            }
        }
        .frame(height: maxHeight)
    }

    private func heightForBar(_ index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        let centerIndex = CGFloat(barCount - 1) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - centerIndex)
        let normalizedDistance = distanceFromCenter / centerIndex

        // Create wave pattern: center bars are taller
        let waveMultiplier = 1.0 - (normalizedDistance * 0.6)

        // Calculate height based on audio level (amplified for sensitivity)
        let amplifiedLevel = min(1.0, level * 1.8)
        let dynamicHeight = minHeight + (maxHeight - minHeight) * amplifiedLevel * waveMultiplier

        // Add slight variation for more organic feel
        let variation = sin(Double(index) * 0.8 + Double(level) * 10) * 0.15 + 1.0

        return max(minHeight, min(maxHeight, dynamicHeight * CGFloat(variation)))
    }
}

// MARK: - Previews

#Preview("Listening Waves - Silent") {
    ListeningDotsView(audioLevel: 0.0)
        .padding()
        .useTheme()
}

#Preview("Listening Waves - Low") {
    ListeningDotsView(audioLevel: 0.3)
        .padding()
        .useTheme()
}

#Preview("Listening Waves - Medium") {
    ListeningDotsView(audioLevel: 0.6)
        .padding()
        .useTheme()
}

#Preview("Listening Waves - High") {
    ListeningDotsView(audioLevel: 1.0)
        .padding()
        .useTheme()
}

#Preview("Listening Waves - Animated") {
    ListeningDotsAnimatedPreview()
}

private struct ListeningDotsAnimatedPreview: View {
    @State private var audioLevel: Float = 0.0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 20) {
            ListeningDotsView(audioLevel: audioLevel)

            Slider(value: Binding(
                get: { Double(audioLevel) },
                set: { audioLevel = Float($0) }
            ), in: 0...1)
            .padding(.horizontal)

            Text("Audio Level: \(String(format: "%.2f", audioLevel))")
                .font(.caption)
        }
        .padding()
        .onAppear {
            // Simulate audio level changes
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                withAnimation {
                    audioLevel = Float.random(in: 0.2...0.8)
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
