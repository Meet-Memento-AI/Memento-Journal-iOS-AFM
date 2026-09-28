//
//  ContentColumn.swift
//  withMemento
//
//  Reading-column caps for central content. iPad gets a measure a person can
//  actually read; iPhone is provably unchanged.
//

import SwiftUI

/// Metrics for the central reading column.
///
/// Two measures, not one, because the surfaces genuinely want different widths:
/// prose read line by line wants the narrower of the two, while a timeline of
/// cards or a chat transcript full of citations and action bars wants more room.
/// Collapsing them to a single number would make one of the two wrong.
///
/// Both are applied unconditionally rather than behind an idiom check. iPhone is
/// portrait-locked, so the widest proposal any phone can make is 440pt and every
/// clamp here resolves to the width the page already had — see
/// `ContentColumnTests`. Only iPad ever reaches a cap.
enum ContentColumnMetrics {
    /// Prose read line by line: onboarding, the entry editor, Settings, Insights.
    /// ~65–75 characters at the Figtree body size.
    static let reading: CGFloat = 600

    /// Surfaces of *objects* rather than lines: the journal timeline, the chat
    /// transcript, and the chrome that has to align with them.
    ///
    /// 720 rather than the ~768 a desktop chat UI would use, because iPad mini is
    /// 744pt in portrait: at 768 the mini would never clamp at all and 11″
    /// portrait (834pt) would clamp by only 33pt — a margin too small to read as
    /// deliberate, which is worse than no margin. 720 gives every iPad in every
    /// orientation a visible margin.
    static let surface: CGFloat = 720

    /// Original name for `reading`. Kept so the onboarding call sites and
    /// `ContentColumnTests` compile untouched — their survival is part of the
    /// evidence that the cap changed nothing that already shipped.
    static let maxWidth: CGFloat = reading
}

// MARK: - Explicit caps

extension View {
    /// Caps and centres central content at a reading-column width.
    ///
    /// A plain proposal clamp, so it is safe inside a `ScrollView` and composes
    /// with an inner `rootEdgeInset()`.
    func contentColumn(_ maxWidth: CGFloat = ContentColumnMetrics.reading) -> some View {
        frame(maxWidth: maxWidth)
    }

    /// Container-relative variant, for hosts under `.ignoresSafeArea()` where a
    /// plain clamp does not pick up the gutter.
    ///
    /// **Never use this inside a `ScrollView`'s content** — see the note at
    /// `ChatMessagesView.contentStack`: `containerRelativeFrame` circularly
    /// depends on content width there and collapses to zero. Applying it *to* a
    /// `ScrollView` is fine, and is what Chat does.
    func contentColumnRelative(_ maxWidth: CGFloat = ContentColumnMetrics.reading) -> some View {
        containerRelativeFrame(.horizontal, alignment: .center) { length, _ in
            min(max(length - AppHeaderMetrics.edgeInset * 2, 0), maxWidth)
        }
    }

    /// Caps and *centres* content that lives inside a `ScrollView`.
    ///
    /// This is the band idiom `OnboardingPageScaffold` already ships (its header,
    /// content and footer each pair a cap with an expansion frame), named so it
    /// can be reviewed against that precedent. The clamp alone leaves the result
    /// at the leading edge and a `ScrollView`'s cross-axis placement of
    /// narrow content is an implementation detail that has moved between
    /// releases; the outer infinity frame re-takes the full proposal and centres
    /// the child, so the question never arises.
    ///
    /// Order matters: apply this *after* `.padding(.horizontal:)` so the gutter
    /// lives inside the cap — outer width is the cap, content is `cap - 2 × gutter`.
    ///
    /// Only for subtrees that are **already** full-width on iPhone. The outer
    /// `.frame(maxWidth: .infinity)` is an iPhone no-op only in that case; on a
    /// bare `VStack(alignment: .leading)`, whose width today is "max child
    /// width", it would change the phone. Cap the `ScrollView` itself there
    /// instead — inert at every phone width by construction.
    func contentColumnCentered(_ maxWidth: CGFloat = ContentColumnMetrics.surface) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Caps prose at the reading measure, centred in the window, with its own
    /// content still leading-aligned. For the `ScrollView { VStack(alignment:
    /// .leading) … }` pages: Settings, Insights, search results.
    ///
    /// Three frames, each load-bearing:
    ///  1. greedy-and-leading *before* the cap, so a page whose copy is short
    ///     does not become a narrow block that step 3 then centres — that would
    ///     move short text to the middle of the screen on iPhone. `SettingsRow`
    ///     is already greedy (it ends in a `Spacer()`), so this is inert there;
    ///     `WeeklyReflectionView`'s bare `Text` column is not, which is why the
    ///     step exists.
    ///  2. the cap itself.
    ///  3. centre the capped block.
    ///
    /// This deliberately goes *inside* the `ScrollView`, leaving the page's
    /// `.background(theme.background.ignoresSafeArea())` full-width. Capping the
    /// `ScrollView` instead would shrink that fill, and these pages are pushed on
    /// `ContentView`'s transparent overlay stack — PRES-023 requires each route to
    /// paint its own opaque fill, or the root pager shows through beside it.
    func proseColumn(_ maxWidth: CGFloat = ContentColumnMetrics.reading) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Page-declared column

private struct ContentColumnWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = ContentColumnMetrics.reading
}

extension EnvironmentValues {
    /// The column width the enclosing page reads its content at.
    ///
    /// Shared chrome must not hardcode a measure: `AppHeader` is mounted by both
    /// root pages, and a header pinned to `surface` above prose capped at
    /// `reading` puts its back control 60pt outside the text column. Root pages
    /// declare `surface`; everything else inherits `reading`, so a page added
    /// later gets the right chrome without touching the header.
    var contentColumnWidth: CGFloat {
        get { self[ContentColumnWidthKey.self] }
        set { self[ContentColumnWidthKey.self] = newValue }
    }
}

/// Reads the page's declared column. A `View` extension cannot read
/// `@Environment`, so the env-driven caps are modifiers.
private struct PageColumnRelative: ViewModifier {
    @Environment(\.contentColumnWidth) private var columnWidth

    func body(content: Content) -> some View {
        content.contentColumnRelative(columnWidth)
    }
}

private struct PageColumnClamp: ViewModifier {
    @Environment(\.contentColumnWidth) private var columnWidth

    func body(content: Content) -> some View {
        content.frame(maxWidth: columnWidth)
    }
}

private struct PageColumnCentered: ViewModifier {
    @Environment(\.contentColumnWidth) private var columnWidth

    func body(content: Content) -> some View {
        content.contentColumnCentered(columnWidth)
    }
}

extension View {
    /// Container-relative cap at the page's declared column. The replacement for
    /// `rootEdgeInset()` on chrome that should align to content rather than the
    /// window.
    func pageColumnRelative() -> some View {
        modifier(PageColumnRelative())
    }

    /// Plain clamp at the page's declared column, for chrome already inside a
    /// centring container (a `.center`-aligned overlay or `safeAreaInset`).
    func pageColumn() -> some View {
        modifier(PageColumnClamp())
    }

    /// Centred cap at the page's declared column, for scroll content. Carries
    /// `contentColumnCentered`'s restriction — full-width subtrees only.
    func pageColumnCentered() -> some View {
        modifier(PageColumnCentered())
    }

    /// Declares the column every descendant caps against.
    func contentColumnWidth(_ width: CGFloat) -> some View {
        environment(\.contentColumnWidth, width)
    }
}
