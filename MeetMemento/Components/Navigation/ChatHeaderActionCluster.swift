//
//  ChatHeaderActionCluster.swift
//  MeetMemento
//
//  Chat's trailing header control: one Liquid Glass capsule that always
//  shows history, then expands to reveal the write (summarize) glyph.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One glass bubble for Chat's trailing actions. Collapsed it is a 48pt
/// capsule with `list.bullet`. When `showsSummarize` is true it grows
/// leftward to fit `square.and.pencil` beside history. Glyphs sit *inside*
/// the capsule's glass — they are not individually glassed, so this remains
/// a single sampling region inside `AppHeader`'s `GlassEffectContainer`.
struct ChatHeaderActionCluster: View {
    var showsSummarize: Bool
    var onSummarize: () -> Void
    var onHistory: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var size: CGFloat { AppHeaderMetrics.controlSize }
    private var clusterWidth: CGFloat {
        showsSummarize ? size * 2 : size
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsSummarize {
                glyphButton(
                    systemName: "square.and.pencil",
                    accessibilityLabel: "Summarise chat",
                    accessibilityHint: "Double-tap to turn this conversation into a journal entry",
                    accessibilityIdentifier: "chat.header.summarize",
                    action: onSummarize
                )
                .entryZoomSource(EntryRoute.createFromChatZoomSourceID)
                .transition(writeTransition)
            }
            glyphButton(
                systemName: "list.bullet",
                accessibilityLabel: "Chat history",
                accessibilityHint: nil,
                accessibilityIdentifier: "chat.header.history",
                action: onHistory
            )
        }
        .frame(width: clusterWidth, height: size)
        .glassEffect(.regular, in: Capsule())
        // Lock layout at rest so the expanding capsule grows left into the
        // header spacer instead of shoving neighbours.
        .frame(width: clusterWidth, height: size)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: showsSummarize)
        .accessibilityElement(children: .contain)
    }

    private var writeTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .scale(scale: 0.6).combined(with: .opacity)
    }

    private func glyphButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityHint: String?,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(theme.foreground)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(ClusterGlyphPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(ClusterOptionalHint(hint: accessibilityHint))
    }
}

/// Press scale on the glyph only. `.interactive()` is not on the capsule —
/// that would scale the whole bubble when either icon is tapped.
private struct ClusterGlyphPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
                value: configuration.isPressed
            )
    }
}

private struct ClusterOptionalHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}
