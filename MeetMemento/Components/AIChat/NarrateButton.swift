//
//  NarrateButton.swift
//  MeetMemento
//
//  Circular button that transforms between Narrate and Send states
//

import SwiftUI

struct NarrateButton: View {
    enum ButtonState {
        case narrate
        case send
        case sending
    }

    var state: ButtonState
    var onTap: () -> Void

    @Environment(\.theme) private var theme

    private let buttonSize: CGFloat = 48

    var body: some View {
        Button(action: {
            triggerHaptic()
            onTap()
        }) {
            ZStack {
                switch state {
                case .narrate:
                    narrateContent
                        .transition(.scale.combined(with: .opacity))
                case .send:
                    sendContent
                        .transition(.scale.combined(with: .opacity))
                case .sending:
                    sendingContent
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: buttonSize, height: buttonSize)
            .background(backgroundForState)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state)
        .accessibilityLabel(accessibilityLabelForState)
        .accessibilityHint(accessibilityHintForState)
    }

    // MARK: - Narrate Content (Voice Wave Icon - 5 bars)

    private var narrateContent: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.foreground)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Create a wave pattern: shorter on edges, taller in middle
        let heights: [CGFloat] = [8, 14, 18, 14, 8]
        return heights[index]
    }

    // MARK: - Send Content

    private var sendContent: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 18, weight: .bold)) // icon-size: not user text
            .foregroundColor(theme.primary)
    }

    // MARK: - Sending Content

    private var sendingContent: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: theme.primary))
            .scaleEffect(0.9)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundForState: some View {
        // Every state sits on the same pure liquid glass — no purple fill, no
        // gray drop shadow. State is conveyed by the icon, not the background.
        glassBackground
    }

    @ViewBuilder
    private var glassBackground: some View {
        // Liquid Glass removed — flat #fafafa surface.
        Circle()
            .fill(Color(hex: "#FAFAFA"))
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        switch state {
        case .narrate:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .send:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .sending:
            break // No haptic for sending state
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabelForState: String {
        switch state {
        case .narrate:
            return "Start voice input"
        case .send:
            return "Send message"
        case .sending:
            return "Sending message"
        }
    }

    private var accessibilityHintForState: String {
        switch state {
        case .narrate:
            return "Double-tap to record your voice"
        case .send:
            return "Double-tap to send"
        case .sending:
            return "Message is being sent"
        }
    }
}

// MARK: - Previews

#Preview("Narrate Button - States") {
    HStack(spacing: 20) {
        VStack {
            NarrateButton(state: .narrate, onTap: {})
            Text("Narrate")
                .font(.caption)
        }
        VStack {
            NarrateButton(state: .send, onTap: {})
            Text("Send")
                .font(.caption)
        }
        VStack {
            NarrateButton(state: .sending, onTap: {})
            Text("Sending")
                .font(.caption)
        }
    }
    .padding()
    .useTheme()
}

#Preview("Narrate Button - Interactive") {
    NarrateButtonInteractivePreview()
        .useTheme()
}

private struct NarrateButtonInteractivePreview: View {
    @State private var buttonState: NarrateButton.ButtonState = .narrate

    var body: some View {
        VStack(spacing: 40) {
            NarrateButton(state: buttonState) {
                switch buttonState {
                case .narrate:
                    buttonState = .send
                case .send:
                    buttonState = .sending
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        buttonState = .narrate
                    }
                case .sending:
                    break
                }
            }

            Text("Current state: \(String(describing: buttonState))")
                .font(.caption)

            Button("Reset") {
                buttonState = .narrate
            }
        }
        .padding()
    }
}
