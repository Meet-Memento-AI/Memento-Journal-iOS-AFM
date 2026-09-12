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
    /// Floor for every Liquid Glass *button* (HIG: ≥44pt hit region). 48pt so a
    /// 12pt gap puts neighbouring centres 60pt apart (Apple's spacing rule).
    /// Icon-only chrome is 48×48; labeled chrome grows only in width.
    static let controlSize: CGFloat = 48
    /// Hit-target floor. Matches `controlSize`.
    static let minimumTapTarget: CGFloat = controlSize
    /// SF Symbol style for glass chrome. Body + semibold is an HIG text
    /// style, so it tracks Dynamic Type instead of a hardcoded point size.
    static var controlSymbolFont: Font { .body.weight(.semibold) }
    /// Bottom pad under the control row, and the 16pt air above the home
    /// indicator (Chat footer / FAB contract).
    static let rowBottomPadding: CGFloat = 16
    /// Left/right inset for root chrome and content (spec 027). Applied as a
    /// width shrink *before* Liquid Glass, not as padding around it.
    static let edgeInset: CGFloat = 16
    /// Breathing room between the header row and the first line of content.
    static let contentGap: CGFloat = 16
    /// Chat composer well — not a button. 8pt inset around 48pt trailing
    /// controls, so the field stays 64pt at rest.
    static let composerMinHeight: CGFloat = controlSize + 16
    /// Floating footer glass (FAB, editor mic/Capture, narration circles).
    /// Taller than header chrome; labeled pills grow only in width.
    static let footerButtonSize: CGFloat = 56

    /// Never smaller than `controlSize`. Larger is for footer FABs (56) and
    /// display-only circles (profile avatar).
    static func glassButtonLength(_ requested: CGFloat) -> CGFloat {
        max(requested, controlSize)
    }

    /// Footer floating glass never drops below `footerButtonSize`.
    static func footerGlassButtonLength(_ requested: CGFloat = footerButtonSize) -> CGFloat {
        max(requested, footerButtonSize)
    }

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

    /// Shared Liquid Glass button chrome. Apply last — after padding and
    /// foreground — so the material samples the 48pt (or larger) frame.
    /// Capsules hug width past 48pt; circles stay square.
    func mementoGlassButtonChrome(
        interactive: Bool = true,
        shape: MementoGlassButtonShape = .capsule,
        minLength: CGFloat = AppHeaderMetrics.controlSize
    ) -> some View {
        mementoGlassButtonChrome(
            .native(interactive: interactive),
            shape: shape,
            minLength: minLength
        )
    }

    func mementoGlassButtonChrome(
        _ glass: Glass,
        shape: MementoGlassButtonShape = .capsule,
        minLength: CGFloat = AppHeaderMetrics.controlSize
    ) -> some View {
        modifier(MementoGlassButtonChrome(
            glass: glass,
            shape: shape,
            minLength: AppHeaderMetrics.glassButtonLength(minLength)
        ))
    }

    /// Floating footer glass: 56×56 floor, width hugs labeled content.
    func mementoFooterGlassButtonChrome(
        interactive: Bool = true,
        shape: MementoGlassButtonShape = .capsule
    ) -> some View {
        mementoGlassButtonChrome(
            interactive: interactive,
            shape: shape,
            minLength: AppHeaderMetrics.footerButtonSize
        )
    }

    func mementoFooterGlassButtonChrome(
        _ glass: Glass,
        shape: MementoGlassButtonShape = .capsule
    ) -> some View {
        mementoGlassButtonChrome(
            glass,
            shape: shape,
            minLength: AppHeaderMetrics.footerButtonSize
        )
    }
}

/// Capsule for labeled / icon chrome; circle for avatar and icon-only FABs.
enum MementoGlassButtonShape {
    case capsule
    case circle
}

private struct MementoGlassButtonChrome: ViewModifier {
    let glass: Glass
    let shape: MementoGlassButtonShape
    let minLength: CGFloat

    func body(content: Content) -> some View {
        switch shape {
        case .capsule:
            content
                .frame(minWidth: minLength, minHeight: minLength)
                .glassEffect(glass, in: .capsule)
                .contentShape(Capsule())
        case .circle:
            content
                .frame(width: minLength, height: minLength)
                .glassEffect(glass, in: .circle)
                .contentShape(Circle())
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

/// A glass icon button. 48pt minimum (HIG hit target + 60pt centre spacing
/// with the 12pt header gap). Width hugs the glyph. No fill under glass.
/// `.interactive()` glass supplies the press scale.
struct HeaderIconButton: View {
    private enum Glyph {
        case system(String)
        case asset(String)
    }

    private let glyph: Glyph
    /// Defaults to `AppHeaderMetrics.controlSize` so Journal and Chat stay matched.
    var size: CGFloat = AppHeaderMetrics.controlSize
    var accessibilityLabel: String
    var accessibilityHint: String?
    /// Override for the glyph. Nil uses `theme.foreground` (black in
    /// light, white in dark). Do not force white on a cover — glass frost
    /// already holds the icon.
    var foreground: Color? = nil
    /// `.interactive()` press refraction. Callers that already hold
    /// `accessibilityReduceMotion` pass `!reduceMotion`; otherwise the
    /// environment is read here so Journal/Chat headers stay in lockstep.
    var interactive: Bool? = nil
    /// Photo-backed chrome may pass a cover-derived wash. Nil is `Glass.native()`.
    var glass: Glass? = nil
    let action: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Figma header glyphs (`ic:outline-lens`, `ic:outline-lens-blur`) are 24pt.
    private static let assetGlyphSize: CGFloat = 24

    init(
        systemName: String,
        size: CGFloat = AppHeaderMetrics.controlSize,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        foreground: Color? = nil,
        interactive: Bool? = nil,
        glass: Glass? = nil,
        action: @escaping () -> Void
    ) {
        self.glyph = .system(systemName)
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.foreground = foreground
        self.interactive = interactive
        self.glass = glass
        self.action = action
    }

    init(
        assetName: String,
        size: CGFloat = AppHeaderMetrics.controlSize,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        foreground: Color? = nil,
        interactive: Bool? = nil,
        glass: Glass? = nil,
        action: @escaping () -> Void
    ) {
        self.glyph = .asset(assetName)
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.foreground = foreground
        self.interactive = interactive
        self.glass = glass
        self.action = action
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            glyphView
                .foregroundStyle(foreground ?? theme.foreground)
                .mementoGlassButtonChrome(resolvedGlass, minLength: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalHint(hint: accessibilityHint))
    }

    @ViewBuilder
    private var glyphView: some View {
        switch glyph {
        case .system(let name):
            Image(systemName: name)
                .font(AppHeaderMetrics.controlSymbolFont)
                .contentTransition(.symbolEffect(.replace))
        case .asset(let name):
            Image(name)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: Self.assetGlyphSize, height: Self.assetGlyphSize)
                .contentTransition(.opacity)
        }
    }

    private var resolvedGlass: Glass {
        glass ?? .native(interactive: interactive ?? !reduceMotion)
    }
}

struct OptionalHint: ViewModifier {
    let hint: String?
    func body(content: Content) -> some View {
        if let hint {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}

/// Press scale on a cluster glyph only. `.interactive()` stays off the
/// shared capsule — that would scale the whole bubble when either icon is tapped.
struct ClusterGlyphPressStyle: ButtonStyle {
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
            #if MEMENTO_AI
            JournalHeaderActionCluster(onSearch: {}, onChat: {})
            #else
            HeaderIconButton(systemName: "magnifyingglass",
                             accessibilityLabel: "Search") {}
            #endif
        }
    }
    .useTheme()
    .useTypography()
}

#if MEMENTO_AI
#Preview("Chat header") {
    ZStack(alignment: .top) {
        LinearGradient(colors: [GrayScale.gray100, GrayScale.gray50],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AppHeader {
            HeaderIconButton(systemName: "book",
                             accessibilityLabel: "Journal") {}
        } trailing: {
            ChatHeaderActionCluster(
                showsSummarize: false,
                onSummarize: {},
                onHistory: {}
            )
        }
    }
    .useTheme()
    .useTypography()
}

#Preview("Chat header expanded") {
    ZStack(alignment: .top) {
        LinearGradient(colors: [GrayScale.gray100, GrayScale.gray50],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        AppHeader {
            HeaderIconButton(systemName: "book",
                             accessibilityLabel: "Journal") {}
        } trailing: {
            ChatHeaderActionCluster(
                showsSummarize: true,
                onSummarize: {},
                onHistory: {}
            )
        }
    }
    .useTheme()
    .useTypography()
}
#endif

