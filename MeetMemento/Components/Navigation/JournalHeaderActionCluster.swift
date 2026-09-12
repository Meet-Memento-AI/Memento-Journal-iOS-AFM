//
//  JournalHeaderActionCluster.swift
//  MeetMemento
//
//  Journal's trailing header control: one Liquid Glass capsule holding
//  Search and Chat side by side, matching ChatHeaderActionCluster.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if MEMENTO_AI

/// One glass bubble for Journal's trailing actions. Search sits on the
/// left (`magnifyingglass`); Chat on the right (`message`). Glyphs sit
/// *inside* the capsule's glass — they are not individually glassed, so
/// this remains a single sampling region inside `AppHeader`'s
/// `GlassEffectContainer`.
struct JournalHeaderActionCluster: View {
    var onSearch: () -> Void
    var onChat: () -> Void

    @Environment(\.theme) private var theme

    private var size: CGFloat { AppHeaderMetrics.controlSize }

    var body: some View {
        HStack(spacing: 0) {
            glyphButton(
                systemName: "magnifyingglass",
                accessibilityLabel: "Search",
                accessibilityHint: nil,
                action: onSearch
            )
            // Top-right, facing its destination: Chat is the page to the
            // right, and a left swipe reveals it. Tap and swipe are the same
            // navigation.
            // Label is "AI chat", NOT "Chat with Memento": the composer's
            // idle button on the chat page already uses that label, and two
            // controls sharing one label is ambiguous for VoiceOver and
            // makes `app.buttons["Chat with Memento"]` resolve to whichever
            // page the pager happens to hand back first.
            glyphButton(
                systemName: "message",
                accessibilityLabel: "AI chat",
                accessibilityHint: "Double-tap to open the AI chat, or swipe left",
                action: onChat
            )
        }
        .mementoGlassButtonChrome(interactive: false)
        .accessibilityElement(children: .contain)
    }

    private func glyphButton(
        systemName: String,
        accessibilityLabel: String,
        accessibilityHint: String?,
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
        .modifier(OptionalHint(hint: accessibilityHint))
    }
}
#endif
