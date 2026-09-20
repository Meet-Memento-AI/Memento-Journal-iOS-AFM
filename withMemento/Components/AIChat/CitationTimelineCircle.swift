//
//  CitationTimelineCircle.swift
//  MeetMemento
//
//  Atom: hollow circle marker on the citations timeline
//

import SwiftUI

/// Hollow circle marker (~12–14pt) for the vertical timeline
struct CitationTimelineCircle: View {
    var diameter: CGFloat = 13
    private let strokeWidth: CGFloat = 3

    @Environment(\.theme) private var theme

    var body: some View {
        Circle()
            .fill(theme.mutedForeground)
            .overlay(
                Circle()
                    .stroke(theme.background, lineWidth: strokeWidth)
            )
            .frame(width: diameter, height: diameter)
    }
}

// MARK: - Previews

#Preview("Citation Timeline Circle") {
    HStack(spacing: 24) {
        CitationTimelineCircle()
        CitationTimelineCircle(diameter: 12)
    }
    .padding()
    .background(BaseColors.white)
    .useTheme()
}
