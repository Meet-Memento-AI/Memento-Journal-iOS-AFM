//
//  ReviewedJournalsList.swift
//  MeetMemento
//
//  The journals an Ask reply drew on, listed above the reply.
//
//  This replaces inline "[ref 1]" markers in the response prose. Anchoring a
//  marker to the right clause is more than the first release warrants, so for
//  now the entries are named once, up front, and the prose stays clean.
//  Inline citations return in a later release.
//
//  Shows date + excerpt: `JournalCitation.entryTitle` is `""` on both
//  production mapping paths (live send and reload-from-store), so a title row
//  would render blank. Plumbing real titles through AskCitation → ChatSource →
//  JournalCitation is worth doing when inline citations come back.
//

import SwiftUI

/// Compact list of the journal entries an answer used, rendered above the reply.
/// Rows are tappable — the tap opens the existing `CitationsBottomSheet`, which
/// shows the full excerpt on the timeline.
struct ReviewedJournalsList: View {
    let citations: [JournalCitation]
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    private var headingText: String {
        citations.count == 1 ? "Reviewed 1 journal" : "Reviewed \(citations.count) journals"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headingText)
                .font(type.body2)
                .fontWeight(.bold)
                .foregroundStyle(theme.primary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(citations) { citation in
                    row(for: citation)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double-tap to view the full entries")
    }

    private func row(for citation: JournalCitation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CitationDateTag(date: citation.entryDate)

            Text(citation.excerpt)
                .font(type.body2)
                .foregroundStyle(theme.mutedForeground)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var accessibilityLabel: String {
        let dates = citations
            .map { DateFormatter.reviewedJournalAccessibility.string(from: $0.entryDate) }
            .joined(separator: ", ")
        return "\(headingText): \(dates)"
    }
}

private extension DateFormatter {
    /// Spoken form for VoiceOver — the visual pill's "Oct 3rd, 2025" reads
    /// poorly aloud.
    static let reviewedJournalAccessibility: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()
}

// MARK: - Previews

#Preview("Reviewed Journals — three") {
    ReviewedJournalsList(
        citations: [
            JournalCitation(
                entryId: UUID(), entryTitle: "", entryDate: Date().addingTimeInterval(-86400 * 2),
                excerpt: "Late night at the office, first real Atlas late night, everyone still at their desks past nine."
            ),
            JournalCitation(
                entryId: UUID(), entryTitle: "", entryDate: Date().addingTimeInterval(-86400 * 9),
                excerpt: "Met my new manager for real today, Priya. She asked what I wanted out of the next year."
            ),
            JournalCitation(
                entryId: UUID(), entryTitle: "", entryDate: Date().addingTimeInterval(-86400 * 31),
                excerpt: "Drizzly commute, nothing special, but I noticed I was not dreading the day."
            )
        ],
        onTap: {}
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Reviewed Journals — one") {
    ReviewedJournalsList(
        citations: [
            JournalCitation(
                entryId: UUID(), entryTitle: "", entryDate: Date(),
                excerpt: "Rain all day, the good kind that makes you want to stay in."
            )
        ],
        onTap: {}
    )
    .padding()
    .useTheme()
    .useTypography()
}
