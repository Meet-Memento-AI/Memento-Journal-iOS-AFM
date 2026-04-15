//
//  CitationPopover.swift
//  MeetMemento
//
//  Popover component showing journal excerpt when tapping a citation badge
//

import SwiftUI

/// Data model for citation popover content
struct CitationPopoverData: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let date: Date
    let excerpt: String
    let entryId: UUID

    init(index: Int, date: Date, excerpt: String, entryId: UUID) {
        self.id = UUID()
        self.index = index
        self.date = date
        self.excerpt = excerpt
        self.entryId = entryId
    }
}

/// Popover view displaying citation excerpt
struct CitationPopover: View {
    let data: CitationPopoverData

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let day = Calendar.current.component(.day, from: data.date)
        let suffix = daySuffix(for: day)
        formatter.dateFormat = "MMMM d'\(suffix)', yyyy"
        return formatter.string(from: data.date)
    }

    private func daySuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Date header
            Text(formattedDate)
                .font(type.captionBold)
                .foregroundStyle(theme.primary)

            // Excerpt text (4 line limit)
            Text(data.excerpt)
                .font(type.body2)
                .foregroundStyle(theme.foreground)
                .lineLimit(4)
                .lineSpacing(type.bodyLineSpacing)
        }
        .padding(12)
        .frame(maxWidth: 280, alignment: .leading)
        .background(theme.popover)
        .clipShape(RoundedRectangle(cornerRadius: theme.radius.md))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Previews

#Preview("Citation Popover") {
    CitationPopover(
        data: CitationPopoverData(
            index: 1,
            date: Date(),
            excerpt: "Today was a challenging day at work. I felt overwhelmed by the number of tasks on my plate, but I managed to prioritize and get through most of them.",
            entryId: UUID()
        )
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Citation Popover - Dark") {
    CitationPopover(
        data: CitationPopoverData(
            index: 2,
            date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!,
            excerpt: "Took a long walk in the park this morning. The fresh air helped clear my mind and I came back feeling refreshed.",
            entryId: UUID()
        )
    )
    .padding()
    .environment(\.colorScheme, .dark)
    .useTheme()
    .useTypography()
    .background(Color.black)
}
