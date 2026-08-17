//
//  NarrationFooter.swift
//  MeetMemento
//
//  Hands-free narration chrome for AIChatView: live transcript card plus
//  mic / status / close bar. Figma 409:5620 / 409:5668.
//

import SwiftUI
import UIKit

/// Footer swap while Chat is narrating. Same 16pt page margin and 64pt
/// circles as the typing composer.
struct NarrationFooter: View {
    @ObservedObject var coordinator: NarrationCoordinator
    var onExit: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    private var accentBrown: Color {
        colorScheme == .dark ? theme.foreground : Color(hex: "#724B31")
    }

    private static let buttonShadow = Color(hex: "#333333").opacity(0.08)

    var body: some View {
        VStack(spacing: 16) {
            transcriptCard
            footerBar
        }
    }

    @ViewBuilder
    private var transcriptCard: some View {
        let transcript = coordinator.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty,
           coordinator.phase == .listening || coordinator.phase == .finalizing {
            Text(transcript)
                .font(type.body1)
                .foregroundStyle(accentBrown)
                .lineLimit(4)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.cardBackground)
                        .shadow(color: Self.buttonShadow, radius: 16, y: 4)
                )
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityLabel("Transcription: \(transcript)")
        }
    }

    private var statusText: String {
        switch coordinator.phase {
        case .idle: return ""
        case .listening: return "Listening…"
        case .finalizing, .awaitingResponse: return "Thinking…"
        case .speaking: return "Speaking…"
        }
    }

    private var footerBar: some View {
        HStack(spacing: 8) {
            NarrationCircleButton(
                systemName: "mic",
                size: AppHeaderMetrics.footerButtonSize,
                shadow: Self.buttonShadow,
                accessibilityLabel: coordinator.phase == .speaking ? "Interrupt" : "Send now",
                accessibilityHint: coordinator.phase == .speaking
                    ? "Double-tap to stop Memento speaking and talk"
                    : "Double-tap to send what you've said without waiting"
            ) {
                coordinator.micTapped()
            }

            Text(statusText)
                .font(.custom("Lora-SemiBold", size: 16, relativeTo: .body))
                .foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)

            NarrationCircleButton(
                systemName: "xmark",
                size: AppHeaderMetrics.footerButtonSize,
                shadow: Self.buttonShadow,
                accessibilityLabel: "End voice conversation",
                accessibilityHint: "Double-tap to return to typing"
            ) {
                onExit()
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: statusText)
    }
}

/// Figma: 64pt translucent circle, soft `#333333`@8% shadow, 24pt glyph.
/// Glass on the glyph's container, same reasoning as `HeaderIconButton`.
private struct NarrationCircleButton: View {
    let systemName: String
    let size: CGFloat
    let shadow: Color
    let accessibilityLabel: String
    var accessibilityHint: String?
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.375, weight: .medium))
                .foregroundStyle(theme.foreground)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
                .shadow(color: shadow, radius: 16, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }
}
