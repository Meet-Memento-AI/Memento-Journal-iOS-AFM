//
//  AppHeader.swift
//  MeetMemento
//
//  The per-page header used by the two root screens.
//  Figma 483:1213 (JournalView) and 483:1235 (AIChatView).
//
//  Each root page owns its own header now. The previous design floated ONE
//  header above both pages and swapped its trailing button depending on which
//  page was showing, which capped the whole app at three controls: a fourth
//  pushed the row past the screen width and, because nothing in it could
//  compress, shifted the entire screen ~12pt off-centre. Per-page headers
//  dissolve that — each page carries only its own controls.
//

import SwiftUI

// MARK: - AppHeader

/// Leading and trailing control clusters over a transparent bar.
///
/// Attach with `.safeAreaInset(edge: .top)` so the page reserves exactly the
/// height the header occupies. The three views that used to hardcode
/// `safeAreaTop + 8 + 44 + 32` to guess that height are gone.
struct AppHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // One sampling region for the row. Glass cannot sample glass, and these
        // controls sit within 12pt of each other — migrating them without a
        // shared container is what read as stacked/double glass in the
        // 2026-08-07 attempt.
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                leading
                Spacer(minLength: 12)
                trailing
            }
            // Figma: px-16, pb-16, and buttons starting at y≈64 — i.e. just
            // below the status bar.
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            // The header owns its status-bar clearance explicitly rather than
            // relying on an ambient safe area. Every root surface in this app
            // is deliberately full-bleed (`ignoresSafeArea(edges: .all)` on the
            // page, the pager and ContentView's stack), so by the time a
            // `safeAreaInset` reaches here there is no inset left to sit in —
            // the buttons rendered clipped by the screen edge, at y = -48 and
            // then y = 45. This is the one remaining copy of a measurement the
            // old shared header duplicated in four files.
            .padding(.top, Self.statusBarClearance)
        }
    }

    /// Top window safe-area inset, or a sane default if no key window is up yet.
    private static var statusBarClearance: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 20
    }
}

// MARK: - Header Icon Button

/// A circular glass icon button sized to the design, with a tap target that
/// always clears Apple's 44pt minimum even when the circle is smaller.
struct HeaderIconButton: View {
    let systemName: String
    /// Figma draws 40pt on Journal and 48pt on Chat.
    var size: CGFloat = 40
    var accessibilityLabel: String
    var accessibilityHint: String?
    let action: () -> Void

    @Environment(\.theme) private var theme

    /// Apple's minimum tap target. A 40pt circle is under it, so the hit area
    /// is expanded without changing what is drawn.
    private static let minimumTapTarget: CGFloat = 44

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            // Glass on the view CONTAINING the glyph, not a layer behind it:
            // only content composited inside the effect gets the system's
            // vibrancy treatment. As a sibling background the glyph keeps its
            // literal token colour and washes out. Same note as
            // `AvatarInitialButton`.
            Image(systemName: systemName)
                .font(.system(size: size * 0.5, weight: .medium)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(
                    minWidth: Self.minimumTapTarget,
                    minHeight: Self.minimumTapTarget
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalHint(hint: accessibilityHint))
    }
}

private struct OptionalHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

// MARK: - Previews

#Preview("Journal header") {
    ZStack(alignment: .top) {
        LinearGradient(colors: [.purple.opacity(0.25), .blue.opacity(0.15)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AppHeader {
            AvatarInitialButton(initial: "S", size: 40, enableHaptic: true,
                                accessibilityLabel: "Menu") {}
        } trailing: {
            HStack(spacing: 12) {
                HeaderIconButton(systemName: "magnifyingglass", size: 40,
                                 accessibilityLabel: "Search") {}
                HeaderIconButton(systemName: "message", size: 40,
                                 accessibilityLabel: "Chat with Memento") {}
            }
        }
    }
    .useTheme()
    .useTypography()
}

#Preview("Chat header") {
    ZStack(alignment: .top) {
        LinearGradient(colors: [.purple.opacity(0.25), .blue.opacity(0.15)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AppHeader {
            HeaderIconButton(systemName: "book", size: 48,
                             accessibilityLabel: "Journal") {}
        } trailing: {
            HeaderIconButton(systemName: "list.bullet", size: 48,
                             accessibilityLabel: "Chat history") {}
        }
    }
    .useTheme()
    .useTypography()
}
