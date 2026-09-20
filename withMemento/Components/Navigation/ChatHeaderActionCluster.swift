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
        .mementoGlassButtonChrome(interactive: false)
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
                .font(AppHeaderMetrics.controlSymbolFont)
                .foregroundStyle(theme.foreground)
                .frame(minWidth: size, minHeight: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(ClusterGlyphPressStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
        .modifier(OptionalHint(hint: accessibilityHint))
    }
}
