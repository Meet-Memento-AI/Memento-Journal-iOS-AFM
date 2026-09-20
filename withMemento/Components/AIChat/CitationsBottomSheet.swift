//
//  CitationsBottomSheet.swift
//  MeetMemento
//
//  Bottom sheet showing journal citations referenced in AI responses
//

import SwiftUI

public struct CitationsBottomSheet: View {
    let citations: [JournalCitation]

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(citations: [JournalCitation]) {
        self.citations = citations
    }

    public var body: some View {
        VStack(spacing: 0) {
            MementoSheetHandle()

            // Header
            Text("Journal citations")
                .font(type.h5)
                .foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)

            // Timeline list of citations
            CitationTimelineList(citations: citations)
        }
        .background(theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .mementoSheetPresentation()
    }
}

// MARK: - Previews

#Preview("Citations Bottom Sheet") {
    CitationsBottomSheet(
        citations: [
            JournalCitation(
                entryId: UUID(),
                entryTitle: "Morning Thoughts",
                entryDate: Date().addingTimeInterval(-86400 * 2),
                excerpt: "Work has been stressful this week. I've been feeling overwhelmed with deadlines and meetings. Taking a walk helped clear my mind."
            ),
            JournalCitation(
                entryId: UUID(),
                entryTitle: "Evening Reflection",
                entryDate: Date().addingTimeInterval(-86400 * 5),
                excerpt: "I noticed I feel more balanced after spending time outside. The fresh air and movement seem to reset my perspective on things."
            )
        ]
    )
    .useTheme()
    .useTypography()
}
