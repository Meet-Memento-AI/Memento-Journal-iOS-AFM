//
//  CitationTimelineItem.swift
//  MeetMemento
//
//  Molecule: one citation row — circle + date tag, then excerpt below
//

import SwiftUI

/// Coordinate space name used so items can report circle position for timeline line
let citationListCoordinateSpace = "citationList"

/// Single citation row: timeline circle, pill date tag, and excerpt text below
struct CitationTimelineItem: View {
    let citation: JournalCitation
    var index: Int = 0

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    private let circleToPillSpacing: CGFloat = 5
    private let tagToTextGap: CGFloat = 8
    private let circleDiameter: CGFloat = 13
    /// Leading padding so excerpt text aligns with pill text (circle + gap + pill horizontal padding)
    private var excerptLeadingPadding: CGFloat { circleDiameter + circleToPillSpacing + 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: tagToTextGap) {
            HStack(alignment: .center, spacing: circleToPillSpacing) {
                CitationTimelineCircle()
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CircleCenterYPreferenceKey.self,
                                value: [CircleCenterYEntry(index: index, y: geo.frame(in: .named(citationListCoordinateSpace)).midY)]
                            )
                        }
                    )

                CitationDateTag(date: citation.entryDate)
            }

            Text(citation.excerpt)
                .font(type.body2)
                .foregroundStyle(theme.mutedForeground)
                .lineSpacing(type.bodyLineSpacing)
                .padding(.leading, excerptLeadingPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Citation Timeline Item") {
    CitationTimelineItem(
        citation: JournalCitation(
            entryId: UUID(),
            entryTitle: "Morning Thoughts",
            entryDate: Date().addingTimeInterval(-86400 * 2),
            excerpt: "You mentioned how you had been struggling with accepting the loss of friendships who used to mean a lot to you."
        )
    )
    .padding(.horizontal, 24)
    .useTheme()
    .useTypography()
}
