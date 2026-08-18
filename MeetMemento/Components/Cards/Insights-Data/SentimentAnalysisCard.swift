//
//  SentimentAnalysisCard.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/13/26.
//

import SwiftUI

/// Sentiment Analysis card matching the reference design
/// Deep purple card with horizontal bar chart and emotion labels
struct SentimentAnalysisCard: View {
    // MARK: - Inputs
    let emotionLabels: [String]
    let emotionValues: [Double]
    var showPercentages: Bool = false

    // MARK: - Environment
    @Environment(\.theme) private var theme

    // MARK: - Computed
    private var total: Double {
        emotionValues.reduce(0, +)
    }

    private func percentage(for value: Double) -> Int {
        guard total > 0 else { return 0 }
        return Int(round((value / total) * 100))
    }

    private func emotionColor(for index: Int) -> Color {
        ChartAccessibilityTokens.emotionColors[index % 5].fill
    }

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header with sparkles icon
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .typographyBody2Bold()
                    .foregroundStyle(theme.accent)

                Text("SENTIMENT ANALYSIS")
                    .typographyCaptionBold()
                    .tracking(0.5)
                    .foregroundStyle(theme.foreground)

                Spacer()
            }

            // Horizontal bar chart
            GeometryReader { geometry in
                HStack(spacing: 4) {
                    ForEach(Array(emotionLabels.enumerated()), id: \.offset) { index, _ in
                        if total > 0 {
                            Capsule()
                                .fill(emotionColor(for: index))
                                .frame(width: barWidth(for: emotionValues[index], availableWidth: geometry.size.width))
                        }
                    }
                }
                .frame(height: 12)
            }
            .frame(height: 12)

            // Legend with dots and labels (no percentages)
            VStack(spacing: 16) {
                ForEach(Array(emotionLabels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 16) {
                        // Colored dot (16px)
                        Circle()
                            .fill(emotionColor(for: index))
                            .frame(width: 16, height: 16)

                        // Emotion label
                        Text(label)
                            .typographyBody1()
                            .foregroundStyle(theme.foreground)

                        Spacer()

                        // Optional percentage
                        if showPercentages {
                            Text("\(percentage(for: emotionValues[index]))%")
                                .typographyBody1()
                                .foregroundStyle(theme.mutedForeground)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Helpers
    /// Calculate proportional bar width
    private func barWidth(for value: Double, availableWidth: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let percentage = value / total
        let totalSpacing = CGFloat(emotionLabels.count - 1) * 4
        let usableWidth = availableWidth - totalSpacing
        return max(0, usableWidth * percentage)
    }
}

// MARK: - Previews

#Preview("Reference Design") {
    ZStack {
        // Gradient background
        LinearGradient(
            gradient: Gradient(colors: [
                PrimaryScale.primary800,
                PrimaryScale.primary700
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        SentimentAnalysisCard(
            emotionLabels: ["Anxiety", "Anticipation", "Fear", "Regret"],
            emotionValues: [50, 20, 18, 12]
        )
        .padding(20)
    }
    .useTheme()
    .useTypography()
}

#Preview("With Percentages") {
    ZStack {
        LinearGradient(
            gradient: Gradient(colors: [
                PrimaryScale.primary800,
                PrimaryScale.primary700
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        SentimentAnalysisCard(
            emotionLabels: ["Anxiety", "Anticipation", "Fear", "Regret"],
            emotionValues: [50, 20, 18, 12],
            showPercentages: true
        )
        .padding(20)
    }
    .useTheme()
    .useTypography()
}

#Preview("Three Emotions") {
    ZStack {
        LinearGradient(
            gradient: Gradient(colors: [
                PrimaryScale.primary800,
                PrimaryScale.primary700
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        SentimentAnalysisCard(
            emotionLabels: ["Joy", "Gratitude", "Excitement"],
            emotionValues: [45, 35, 20]
        )
        .padding(20)
    }
    .useTheme()
    .useTypography()
}

#Preview("Five Emotions") {
    ZStack {
        LinearGradient(
            gradient: Gradient(colors: [
                PrimaryScale.primary800,
                PrimaryScale.primary700
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        SentimentAnalysisCard(
            emotionLabels: ["Happy", "Sad", "Angry", "Fearful", "Calm"],
            emotionValues: [30, 25, 20, 15, 10],
            showPercentages: true
        )
        .padding(20)
    }
    .useTheme()
    .useTypography()
}
