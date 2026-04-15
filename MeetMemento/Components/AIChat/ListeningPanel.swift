//
//  ListeningPanel.swift
//  MeetMemento
//
//  Full listening UI panel for voice recording with back/done buttons
//

import SwiftUI

struct ListeningPanel: View {
    var onBack: () -> Void
    var onDone: () -> Void
    var audioLevel: Float

    @Environment(\.theme) private var theme

    private let panelHeight: CGFloat = 200
    private let cornerRadius: CGFloat = 24
    private let buttonSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            // Top row: Back + Done buttons
            HStack {
                backButton
                Spacer()
                doneButton
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            Spacer()

            // Center: Animated dots
            ListeningDotsView(audioLevel: audioLevel)

            Spacer()

            // Label
            Text("Listening")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(theme.primary)
                .padding(.bottom, 24)
        }
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity)
        .background(glassBackground)
    }

    // MARK: - Back Button

    private var backButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.primary)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(PrimaryScale.primary100)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cancel recording")
        .accessibilityHint("Double-tap to cancel and go back")
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onDone()
        } label: {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: buttonSize, height: buttonSize)
                .background(
                    Circle()
                        .fill(theme.primary)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Confirm recording")
        .accessibilityHint("Double-tap to stop recording and send")
    }

    // MARK: - Glass Background

    @ViewBuilder
    private var glassBackground: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.glassFill)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .shadow(
                    color: GlassShadow.color.opacity(GlassShadow.opacity),
                    radius: GlassShadow.blur,
                    x: 0,
                    y: GlassShadow.offsetY
                )
        } else {
            fallbackGlassBackground
        }
        #else
        fallbackGlassBackground
        #endif
    }

    @ViewBuilder
    private var fallbackGlassBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .shadow(
                color: GlassShadow.color.opacity(GlassShadow.opacity),
                radius: GlassShadow.blur,
                x: 0,
                y: GlassShadow.offsetY
            )
    }
}

// MARK: - Previews

#Preview("Listening Panel") {
    VStack {
        Spacer()
        ListeningPanel(
            onBack: { print("Back tapped") },
            onDone: { print("Done tapped") },
            audioLevel: 0.5
        )
        .padding(.horizontal, 20)
    }
    .useTheme()
}

#Preview("Listening Panel - Animated") {
    ListeningPanelAnimatedPreview()
        .useTheme()
}

private struct ListeningPanelAnimatedPreview: View {
    @State private var audioLevel: Float = 0.0
    @State private var timer: Timer?

    var body: some View {
        VStack {
            Spacer()
            ListeningPanel(
                onBack: { print("Back tapped") },
                onDone: { print("Done tapped") },
                audioLevel: audioLevel
            )
            .padding(.horizontal, 20)
        }
        .onAppear {
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

#Preview("Listening Panel - Dark") {
    VStack {
        Spacer()
        ListeningPanel(
            onBack: { print("Back tapped") },
            onDone: { print("Done tapped") },
            audioLevel: 0.6
        )
        .padding(.horizontal, 20)
    }
    .useTheme()
    .preferredColorScheme(.dark)
}
