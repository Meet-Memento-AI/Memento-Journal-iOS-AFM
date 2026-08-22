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
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared metrics

/// Drawn diameter and padding for every control in `AppHeader`.
/// Journal and Chat (including Chat's narration mode) all use these so chrome stays matched.
enum AppHeaderMetrics {
    /// Drawn diameter for every header / nav glass icon button.
    static let controlSize: CGFloat = 48
    /// Hit-target floor. Matches `controlSize` now that controls clear Apple's
    /// 44pt minimum on their own; kept so smaller sizes still expand cleanly.
    static let minimumTapTarget: CGFloat = max(44, controlSize)
    /// Bottom pad under the control row, and the 16pt air above the home
    /// indicator (Chat footer / FAB contract).
    static let rowBottomPadding: CGFloat = 16
    /// Left/right inset for root chrome and content (spec 027). Applied as a
    /// width shrink *before* Liquid Glass, not as padding around it.
    static let edgeInset: CGFloat = 16
    /// Breathing room between the header row and the first line of content.
    static let contentGap: CGFloat = 16
    /// Footer / FAB circle diameter (Narration footer buttons and ChatInputField).
    static let footerButtonSize: CGFloat = 64

    /// Status-bar / Dynamic Island inset from the key window. Root pages
    /// ignore the system safe area and apply this as padding on the header.
    static var windowTop: CGFloat { windowSafeArea.top }
    /// Home-indicator inset from the key window. Applied under the footer
    /// together with `rowBottomPadding` (16pt).
    static var windowBottom: CGFloat { windowSafeArea.bottom }

    /// Overlay header occupies this much below the physical top
    /// (`windowTop` + 48pt controls + 16pt row pad).
    static var headerClearance: CGFloat { windowTop + controlSize + rowBottomPadding }
    /// First line of scroll content: header clearance plus 16pt air.
    static var contentTopPadding: CGFloat { headerClearance + contentGap }

    /// Air between the header row's bottom edge and the pinned user message in
    /// Chat's send choreography. Chat-only — do NOT fold this into
    /// `contentGap`, which Journal and the rest of the app share.
    static let chatPinGap: CGFloat = Spacing.xxl

    /// Top safe-area inset for the Chat transcript. A safe-area inset (unlike
    /// `.padding`) shrinks the scroll view's *visible* rect, which is the rect
    /// `ScrollViewProxy.scrollTo(_:anchor:)` resolves against — so `anchor:
    /// .top` lands on the pin for every message, not just the first one.
    static var chatPinTopInset: CGFloat { headerClearance + chatPinGap }

    private static var windowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }
}

extension View {
    /// Shrinks this view to `container width - 2 × edgeInset` before glass
    /// samples. Padding around `glassEffect` is ignored on root pages that
    /// call `.ignoresSafeArea()`; this is not.
    func rootEdgeInset() -> some View {
        containerRelativeFrame(.horizontal, alignment: .center) { length, _ in
            max(length - AppHeaderMetrics.edgeInset * 2, 0)
        }
    }
}

// MARK: - AppHeader

/// Leading and trailing control clusters over a transparent bar.
///
/// The overlay is pinned to the physical top of the frame. A `windowTop`
/// spacer stretches through the Dynamic Island / status bar; the glass row
/// sits on that safe-area guide (16pt sides, 16pt below the row). Blur lives
/// only in the island strip — never behind the buttons — so glass can sample
/// the scrolling content.
struct AppHeader<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: AppHeaderMetrics.windowTop)
                .frame(maxWidth: .infinity)
                .background {
                    ProgressiveBlurEdge(
                        edge: .top,
                        height: AppHeaderMetrics.windowTop
                    )
                }
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // One sampling region for the row. Glass cannot sample glass, and
            // these controls sit within 12pt of each other — migrating them
            // without a shared container is what read as stacked/double glass
            // in the 2026-08-07 attempt.
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    leading
                    Spacer(minLength: 12)
                    trailing
                }
                .padding(.bottom, AppHeaderMetrics.rowBottomPadding)
                .rootEdgeInset()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Header Icon Button

/// A circular glass icon button. Layout stays at `size` at rest;
/// `.interactive()` glass supplies the press scale.
struct HeaderIconButton: View {
    let systemName: String
    /// Defaults to `AppHeaderMetrics.controlSize` so Journal and Chat stay matched.
    var size: CGFloat = AppHeaderMetrics.controlSize
    var accessibilityLabel: String
    var accessibilityHint: String?
    let action: () -> Void

    @Environment(\.theme) private var theme

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
                // Lock layout at rest. `.interactive()` still scales the glass
                // on press; this outer frame keeps neighbours from shifting.
                .frame(width: size, height: size)
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
        LinearGradient(colors: [GrayScale.gray100, GrayScale.gray50],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AppHeader {
            AvatarInitialButton(initial: "S", size: AppHeaderMetrics.controlSize,
                                enableHaptic: true, accessibilityLabel: "Menu") {}
        } trailing: {
            HStack(spacing: 12) {
                HeaderIconButton(systemName: "magnifyingglass",
                                 accessibilityLabel: "Search") {}
                HeaderIconButton(systemName: "message",
                                 accessibilityLabel: "Chat with Memento") {}
            }
        }
    }
    .useTheme()
    .useTypography()
}

#Preview("Chat header") {
    ZStack(alignment: .top) {
        LinearGradient(colors: [GrayScale.gray100, GrayScale.gray50],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AppHeader {
            HeaderIconButton(systemName: "book",
                             accessibilityLabel: "Journal") {}
        } trailing: {
            HStack(spacing: 12) {
                HeaderIconButton(systemName: "sparkles",
                                 accessibilityLabel: "Summarise chat") {}
                HeaderIconButton(systemName: "list.bullet",
                                 accessibilityLabel: "Chat history") {}
            }
        }
    }
    .useTheme()
    .useTypography()
}
