//
//  MementoSheetChrome.swift
//  withMemento
//
//  Shared house sheet chrome: drag handle, corner radius, primary glass tint.
//  Compose sheets (Summary, Report) and list sheets (History, Citations,
//  Profile) share one handle so padding does not drift.
//

import SwiftUI

enum MementoSheetChrome {
    /// Same interior tint as Welcome Get Started / ChatSummarySheet.
    static let primaryGlassTintOpacity: Double = 0.24

    static var primaryGlass: Glass {
        .regular.tint(BaseColors.black.opacity(primaryGlassTintOpacity))
    }
}

/// House drag handle. The system indicator is hidden so this is the only
/// affordance (`mementoSheetPresentation`).
struct MementoSheetHandle: View {
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(theme.mutedForeground.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.lg)
            .accessibilityHidden(true)
    }
}

struct MementoSheetPresentation: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .contentColumnSafeArea()
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(theme.radius.xxl)
    }
}

extension View {
    func mementoSheetPresentation() -> some View {
        modifier(MementoSheetPresentation())
    }

    /// Regular width only: sizes a centred sheet to the 600pt reading column
    /// (page height) and rims it with `theme.border`. Without the rim a dark
    /// sheet has no visible edge on the dimmed page and reads as content
    /// overlapping the journal. Compact sheets are untouched.
    func mementoColumnSheet() -> some View {
        modifier(MementoColumnSheet())
    }
}

/// The system form sheet is narrower than `ContentColumnMetrics.maxWidth`,
/// which left sheet rows inside the page column's edges.
struct ColumnSheetSizing: PresentationSizing {
    func proposedSize(
        for root: PresentationSizingRoot,
        context: PresentationSizingContext
    ) -> ProposedViewSize {
        let page = PagePresentationSizing.page.proposedSize(for: root, context: context)
        return ProposedViewSize(width: ContentColumnMetrics.maxWidth, height: page.height)
    }
}

private struct MementoColumnSheet: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: theme.radius.xxl, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .presentationSizing(ColumnSheetSizing())
        } else {
            content
        }
    }
}
