//
//  WordCounterNavButton.swift
//  MeetMemento
//
//  Navigation button that displays character count progress as a pie chart
//  Transitions to a filled checkmark when minimum character count is reached
//

import SwiftUI
import UIKit

public struct WordCounterNavButton: View {
    // MARK: - Environment
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // MARK: - Properties
    let characterCount: Int
    let minimumCharacters: Int
    let buttonSize: CGFloat
    var onTap: (() -> Void)?

    // MARK: - State
    @State private var isPressed = false

    // MARK: - Computed Properties
    private var progress: CGFloat {
        guard minimumCharacters > 0 else { return 1.0 }
        return min(CGFloat(characterCount) / CGFloat(minimumCharacters), 1.0)
    }

    private var isComplete: Bool {
        progress >= 1.0
    }

    private var isEmpty: Bool {
        characterCount == 0
    }

    // MARK: - Initializer
    public init(
        characterCount: Int,
        minimumCharacters: Int,
        // Literal: this init is `public`, so it cannot default to internal
        // `AppHeaderMetrics.controlSize` (48). Keep the number in sync.
        buttonSize: CGFloat = 48,
        onTap: (() -> Void)? = nil
    ) {
        self.characterCount = characterCount
        self.minimumCharacters = minimumCharacters
        self.buttonSize = buttonSize
        self.onTap = onTap
    }

    // MARK: - Body
    public var body: some View {
        Button {
            guard isComplete else { return }
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            onTap?()
        } label: {
            ZStack {
                // No background material — lives inside toolbar's liquid glass
                if isEmpty {
                    emptyStateIcon
                } else if isComplete {
                    completedStateIcon
                } else {
                    progressPieChart
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isComplete)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isComplete)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressed && isComplete {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    isPressed = false
                }
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    // MARK: - Subviews

    private var emptyStateIcon: some View {
        Image(systemName: "checkmark.circle")
            .font(.system(size: buttonSize * 0.6, weight: .bold)) // icon-size: not user text
            .foregroundStyle(theme.mutedForeground.opacity(0.5))
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    private var completedStateIcon: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: buttonSize * 0.6, weight: .bold)) // icon-size: not user text
            .foregroundStyle(theme.accent)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private var progressPieChart: some View {
        ZStack {
            // Subtle track ring
            Circle()
                .stroke(theme.border.opacity(0.6), lineWidth: 1.5)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    theme.accent.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)

            Text("\(characterCount)")
                .font(type.microMedium)
                .foregroundStyle(theme.foreground)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
        .padding(4)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        if isComplete {
            return "Continue, minimum characters reached"
        } else if isEmpty {
            return "Continue button, enter \(minimumCharacters) characters to continue"
        } else {
            return "Continue button, \(characterCount) of \(minimumCharacters) characters entered"
        }
    }

    private var accessibilityHint: String {
        if isComplete {
            return "Double-tap to continue"
        } else {
            let remaining = minimumCharacters - characterCount
            return "Enter \(remaining) more character\(remaining == 1 ? "" : "s") to continue"
        }
    }
}

// MARK: - Previews

#Preview("Empty State") {
    EmptyStatePreview()
}

#Preview("In Progress - 30%") {
    ProgressPreview(count: 30)
}

#Preview("In Progress - 75%") {
    ProgressPreview(count: 75)
}

#Preview("Complete") {
    CompletePreview()
}

#Preview("Interactive Demo") {
    InteractiveDemoView()
}

// MARK: - Preview Helpers

private struct EmptyStatePreview: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            WordCounterNavButton(
                characterCount: 0,
                minimumCharacters: 100,
                buttonSize: AppHeaderMetrics.controlSize
            )
        }
        .useTheme()
    }
}

private struct ProgressPreview: View {
    @Environment(\.theme) private var theme
    let count: Int

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            WordCounterNavButton(
                characterCount: count,
                minimumCharacters: 100,
                buttonSize: AppHeaderMetrics.controlSize
            )
        }
        .useTheme()
    }
}

private struct CompletePreview: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            WordCounterNavButton(
                characterCount: 125,
                minimumCharacters: 100,
                buttonSize: AppHeaderMetrics.controlSize
            )
        }
        .useTheme()
    }
}

private struct InteractiveDemoView: View {
    @Environment(\.theme) private var theme
    @State private var text: String = ""

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Type to see progress")
                    .typographyH4()

                WordCounterNavButton(
                    characterCount: text.count,
                    minimumCharacters: 100,
                    buttonSize: AppHeaderMetrics.controlSize,
                    onTap: {
                        AppLogger.log("✅ Minimum character count reached!")
                    }
                )

                TextEditor(text: $text)
                    .frame(height: 150)
                    .padding(12)
                    .background(theme.cardBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.border, lineWidth: 1)
                    )

                HStack {
                    Text("\(text.count) / 100 characters")
                        .typographyBody2()
                        .foregroundStyle(text.count >= 100 ? theme.accent : theme.mutedForeground)

                    Spacer()

                    if text.count >= 100 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding()
        }
        .useTheme()
        .useTypography()
    }
}
