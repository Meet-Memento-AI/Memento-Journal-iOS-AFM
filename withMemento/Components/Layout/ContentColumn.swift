//
//  ContentColumn.swift
//  withMemento
//
//  Reading-column cap for central content. iPad gets a measure a person can
//  actually read; iPhone is provably unchanged.
//

import SwiftUI

/// Metrics for the central reading column.
///
/// iPhone portrait-lock is the 1.x contract, not an accident — see
/// `docs/app-store/14-orientation-decision.md` before enabling iPhone landscape.
enum ContentColumnMetrics {
    /// Reading-column cap.
    ///
    /// Applied unconditionally rather than behind an idiom check. iPhone is
    /// portrait-locked, so the widest proposal any phone can make is 440pt and
    /// `min(width - 2 * edgeInset, 600)` always resolves to the width the page
    /// already had — see `ContentColumnTests`. Only iPad ever reaches the cap.
    static let maxWidth: CGFloat = 600

    /// Width of the column itself: the container, capped.
    static func columnWidth(in container: CGFloat) -> CGFloat {
        min(container, maxWidth)
    }

    /// Width inside the column once the shared `AppHeaderMetrics.edgeInset`
    /// gutter is taken off both sides. What `rootEdgeInset()` resolves to.
    static func insetWidth(in container: CGFloat) -> CGFloat {
        max(columnWidth(in: container) - AppHeaderMetrics.edgeInset * 2, 0)
    }

    /// Horizontal safe-area padding that centres a full-width page on the
    /// column. Zero whenever the container is no wider than the column.
    static func sideInset(in container: CGFloat) -> CGFloat {
        max((container - maxWidth) / 2, 0)
    }
}

extension View {
    /// Caps and centres central content at the reading-column width.
    ///
    /// A plain proposal clamp, so it is safe inside a `ScrollView` and composes
    /// with an inner `rootEdgeInset()`.
    func contentColumn(_ maxWidth: CGFloat = ContentColumnMetrics.maxWidth) -> some View {
        frame(maxWidth: maxWidth)
    }

    /// Safe-area variant, for whole pages and sheets that should keep
    /// full-width backgrounds, scrolling and navigation bars while their
    /// content sits on the column. Adds horizontal safe area rather than a
    /// frame, so `.ignoresSafeArea()` fills and scroll indicators are
    /// unaffected. Zero at every width up to the column, so iPhone is inert.
    func contentColumnSafeArea() -> some View {
        modifier(ContentColumnSafeArea())
    }

    /// Container-relative variant, for hosts under `.ignoresSafeArea()` where a
    /// plain clamp does not pick up the gutter.
    ///
    /// **Never use this inside a `ScrollView`** — see the note at
    /// `ChatMessagesView.contentStack`: `containerRelativeFrame` circularly
    /// depends on content width there and collapses to zero.
    // periphery:ignore - no caller yet; kept for full-bleed iPad hosts; retained deliberately
    func contentColumnRelative(_ maxWidth: CGFloat = ContentColumnMetrics.maxWidth) -> some View {
        containerRelativeFrame(.horizontal, alignment: .center) { length, _ in
            min(max(length - AppHeaderMetrics.edgeInset * 2, 0), maxWidth)
        }
    }
}

private struct ContentColumnSafeArea: ViewModifier {
    @State private var containerWidth: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.horizontal, ContentColumnMetrics.sideInset(in: containerWidth))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
    }
}
