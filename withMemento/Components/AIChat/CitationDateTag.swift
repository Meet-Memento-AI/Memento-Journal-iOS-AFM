//
//  CitationDateTag.swift
//  MeetMemento
//
//  Atom: pill-shaped date tag for journal citations timeline
//

import SwiftUI

/// Pill-shaped label showing citation date (e.g. "Oct 3rd, 2025")
struct CitationDateTag: View {
    let date: Date

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    var body: some View {
        Text(ordinalDateString(from: date))
            .font(type.captionMedium)
            .foregroundStyle(theme.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(theme.mutedForeground.opacity(0.15))
            )
    }

    /// "Oct 3rd, 2025" style: MMM + ordinal day + ", " + yyyy
    private func ordinalDateString(from date: Date) -> String {
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let ordinal = ordinalSuffix(for: day)
        let month = monthFormatter.string(from: date)
        let year = yearFormatter.string(from: date)
        return "\(month) \(day)\(ordinal), \(year)"
    }

    private func ordinalSuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31: return "st"
        case 2, 22: return "nd"
        case 3, 23: return "rd"
        default: return "th"
        }
    }
}

// MARK: - Previews

#Preview("Citation Date Tag") {
    VStack(spacing: 12) {
        CitationDateTag(date: Date())
        CitationDateTag(date: Date().addingTimeInterval(-86400 * 2))
        CitationDateTag(date: Date().addingTimeInterval(-86400 * 31))
    }
    .padding()
    .useTheme()
    .useTypography()
}
