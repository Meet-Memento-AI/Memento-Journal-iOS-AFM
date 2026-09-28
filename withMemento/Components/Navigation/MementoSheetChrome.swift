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
}
