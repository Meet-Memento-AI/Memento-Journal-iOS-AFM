//
//  InsightDateTag.swift
//  MeetMemento
//
//  A compact, pill-shaped tag for displaying dates in insights
//  Design inspired by date-tag.svg with purple background and white text
//

import SwiftUI

public struct InsightDateTag: View {
    @Environment(\.typography) private var type

    let date: Date

    // Optional customization
    var format: DateFormat = .short

    public init(date: Date, format: DateFormat = .short) {
        self.date = date
        self.format = format
    }

    // Convenience initializer for string dates (YYYY-MM-DD)
    public init(dateString: String, format: DateFormat = .short) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        self.date = formatter.date(from: dateString) ?? Date()
        self.format = format
    }

    public var body: some View {
        HStack(spacing: 6) {
            // Small circle indicator (like SVG)
            Circle()
                .fill(InsightDateTag.lightText)
                .frame(width: 8, height: 8)

            // Formatted date text
            Text(formattedDate)
                .font(type.captionMedium)
                .foregroundColor(InsightDateTag.lightText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(InsightDateTag.purpleBackground)
        )
    }

    // Format date based on specified format
    private var formattedDate: String {
        let formatter = DateFormatter()

        switch format {
        case .short:
            // "Jan 15"
            formatter.dateFormat = "MMM d"
        case .medium:
            // "Jan 15, 2025"
            formatter.dateFormat = "MMM d, yyyy"
        case .long:
            // "January 15, 2025"
            formatter.dateFormat = "MMMM d, yyyy"
        case .dayMonth:
            // "15 Jan"
            formatter.dateFormat = "d MMM"
        case .relative:
            // "Today", "Yesterday", or date
            return relativeDateString()
        }

        return formatter.string(from: date)
    }

    // Generate relative date strings
    private func relativeDateString() -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
            // Within this week - show day name
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            // Older - show "Jan 15"
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Date Format Options

public extension InsightDateTag {
    enum DateFormat {
        case short      // Jan 15
        case medium     // Jan 15, 2025
        case long       // January 15, 2025
        case dayMonth   // 15 Jan
        case relative   // Today, Yesterday, etc.
    }
}

// MARK: - Colors

private extension InsightDateTag {
    static let purpleBackground = PrimaryScale.primary500  // #7B3EC9
    static let lightText = PrimaryScale.primary50  // #F2EEFC
}

// MARK: - Previews

#Preview("Short Format") {
    VStack(spacing: 12) {
        InsightDateTag(date: Date(), format: .short)
        InsightDateTag(date: Date().addingTimeInterval(-86400), format: .short)
        InsightDateTag(dateString: "2025-01-15", format: .short)
    }
    .padding()
    .background(Color.black)
}

#Preview("All Formats") {
    VStack(alignment: .leading, spacing: 12) {
        Text("Format Examples").font(.headline).foregroundColor(.white)

        InsightDateTag(date: Date(), format: .short)
        InsightDateTag(date: Date(), format: .medium)
        InsightDateTag(date: Date(), format: .long)
        InsightDateTag(date: Date(), format: .dayMonth)
        InsightDateTag(date: Date(), format: .relative)

        Text("Yesterday").font(.caption).foregroundColor(.gray)
        InsightDateTag(date: Date().addingTimeInterval(-86400), format: .relative)

        Text("Last Week").font(.caption).foregroundColor(.gray)
        InsightDateTag(date: Date().addingTimeInterval(-86400 * 7), format: .relative)
    }
    .padding()
    .background(Color.black)
}

#Preview("In Context") {
    ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            // Example: Theme with date tags
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("📊 Work Performance Anxiety")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }

                Text("You're holding yourself to impossibly high standards and replaying mistakes, even when others see you succeeding.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))

                HStack(spacing: 8) {
                    Text("Mentioned in:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))

                    InsightDateTag(dateString: "2025-01-15", format: .short)
                    InsightDateTag(dateString: "2025-01-18", format: .short)
                }
                .padding(.top, 4)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .padding()
    }
    .background(Color.black)
}

#Preview("Light Mode") {
    VStack(spacing: 12) {
        InsightDateTag(date: Date(), format: .short)
        InsightDateTag(date: Date(), format: .medium)
        InsightDateTag(date: Date(), format: .relative)
    }
    .padding()
    .background(Color.white)
}
