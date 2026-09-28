//
//  CitationTimelineItem.swift
//  MeetMemento
//
//  Molecule: one citation row — circle + date tag, then excerpt below
//

import SwiftUI

/// Coordinate space name used so items can report circle position for timeline line
let citationListCoordinateSpace = "citationList"

/// Single citation row: timeline circle, pill date tag, optional ref badge + theme, and excerpt text below
struct CitationTimelineItem: View {
    let citation: JournalCitation
    var index: Int = 0
    /// Optional inline citation ref number (e.g. 1 for [1])
    var refNumber: Int?
    /// Optional theme label from inline citation (e.g. "work stress")
    var theme: String?

    @Environment(\.theme) private var themeEnv
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

                // Ref badge (if inline citation)
                if let ref = refNumber {
                    InlineCitationBadge(ref: ref)
                }

                CitationDateTag(date: citation.entryDate)

                // Theme tag (if inline citation)
                if let themeLabel = theme, !themeLabel.isEmpty {
                    Text(themeLabel)
                        .font(type.caption)
                        .foregroundStyle(themeEnv.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(themeEnv.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Text(citation.excerpt)
                .font(type.body2)
                .foregroundStyle(themeEnv.mutedForeground)
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
