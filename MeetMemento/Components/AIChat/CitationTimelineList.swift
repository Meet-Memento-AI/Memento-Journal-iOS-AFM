//
//  CitationTimelineList.swift
//  MeetMemento
//
//  Organism: vertical timeline with list of citation items
//

import SwiftUI

private let circleDiameter: CGFloat = 13
private let lineWidth: CGFloat = 1.5
private let contentLeading: CGFloat = 24
// Line centered on circles: content leading + circle center - half line width
private var lineCenterX: CGFloat { contentLeading + circleDiameter / 2 - lineWidth / 2 }
private let itemSpacing: CGFloat = 20

struct CircleCenterYEntry: Equatable {
    let index: Int
    let y: CGFloat
}

struct CircleCenterYPreferenceKey: PreferenceKey {
    static var defaultValue: [CircleCenterYEntry] { [] }
    static func reduce(value: inout [CircleCenterYEntry], nextValue: () -> [CircleCenterYEntry]) {
        value.append(contentsOf: nextValue())
    }
}

/// Vertical timeline with hollow circle markers and list of citations
struct CitationTimelineList: View {
    let citations: [JournalCitation]
    /// Inline citation data with ref numbers and themes (optional).
    var inlineCitations: [InlineCitationInfo]?
    /// If set, auto-scroll to and highlight this citation ref.
    var highlightedRef: Int?

    @Environment(\.theme) private var theme
    @State private var firstCircleY: CGFloat?
    @State private var lastCircleY: CGFloat?

    /// Finds inline citation info for a given JournalCitation by matching entryId.
    private func inlineCitationFor(_ citation: JournalCitation) -> InlineCitationInfo? {
        inlineCitations?.first { $0.entryId == citation.entryId }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: itemSpacing) {
                ForEach(Array(citations.enumerated()), id: \.element.id) { index, citation in
                    let inlineInfo = inlineCitationFor(citation)
                    CitationTimelineItem(
                        citation: citation,
                        index: index,
                        refNumber: inlineInfo?.ref,
                        theme: inlineInfo?.theme
                    )
                    .id(inlineInfo?.ref ?? -index)
                }
            }
            .padding(.leading, contentLeading)
            .padding(.trailing, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .coordinateSpace(name: citationListCoordinateSpace)
            .onPreferenceChange(CircleCenterYPreferenceKey.self) { entries in
                let sorted = entries.sorted(by: { $0.index < $1.index })
                firstCircleY = sorted.first?.y
                lastCircleY = sorted.last?.y
            }
            .background(alignment: .leading) {
                GeometryReader { geo in
                    if let first = firstCircleY, let last = lastCircleY, first < last {
                        Rectangle()
                            .fill(theme.mutedForeground.opacity(0.35))
                            .frame(width: lineWidth, height: last - first)
                            .offset(x: lineCenterX, y: first)
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .onAppear {
            // Auto-scroll to highlighted citation if set
            if let ref = highlightedRef {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(ref, anchor: .center)
                    }
                }
            }
        }
        } // ScrollViewReader
    }
}

// MARK: - Previews

#Preview("Citation Timeline List") {
    CitationTimelineList(
        citations: [
            JournalCitation(
                entryId: UUID(),
                entryTitle: "Morning Thoughts",
                entryDate: Date().addingTimeInterval(-86400 * 2),
                excerpt: "You mentioned how you had been struggling with accepting the loss of friendships who used to mean a lot to you."
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
