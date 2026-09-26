//
//  ContentColumn.swift
//  withMemento
//
//  Reading-column cap for central content. iPad gets a measure a person can
//  actually read; iPhone is provably unchanged.
//

import SwiftUI

/// Metrics for the central reading column.
enum ContentColumnMetrics {
    /// Reading-column cap.
    ///
    /// Applied unconditionally rather than behind an idiom check. iPhone is
    /// portrait-locked, so the widest proposal any phone can make is 440pt and
    /// `min(width - 2 * edgeInset, 600)` always resolves to the width the page
    /// already had — see `ContentColumnTests`. Only iPad ever reaches the cap.
    static let maxWidth: CGFloat = 600
}

extension View {
    /// Caps and centres central content at the reading-column width.
    ///
    /// A plain proposal clamp, so it is safe inside a `ScrollView` and composes
    /// with an inner `rootEdgeInset()`.
    func contentColumn(_ maxWidth: CGFloat = ContentColumnMetrics.maxWidth) -> some View {
        frame(maxWidth: maxWidth)
    }

    /// Container-relative variant, for hosts under `.ignoresSafeArea()` where a
    /// plain clamp does not pick up the gutter.
    ///
    /// **Never use this inside a `ScrollView`** — see the note at
    /// `ChatMessagesView.contentStack`: `containerRelativeFrame` circularly
    /// depends on content width there and collapses to zero.
    func contentColumnRelative(_ maxWidth: CGFloat = ContentColumnMetrics.maxWidth) -> some View {
        containerRelativeFrame(.horizontal, alignment: .center) { length, _ in
            min(max(length - AppHeaderMetrics.edgeInset * 2, 0), maxWidth)
        }
    }
}
