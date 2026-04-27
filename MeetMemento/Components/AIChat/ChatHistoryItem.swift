//
//  ChatHistoryItem.swift
//  MeetMemento
//
//  Individual chat session item for history list
//

import SwiftUI

public struct ChatHistoryItem: View {
    let session: ChatSession
    let onTap: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme

    public init(session: ChatSession, onTap: @escaping () -> Void) {
        self.session = session
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        }) {
            HStack(alignment: .center, spacing: 12) {
                // Title (first message sent)
                Text(session.title)
                    .font(type.body1)
                    .foregroundStyle(theme.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Creation date
                Text(formattedDate)
                    .font(type.caption)
                    .foregroundStyle(theme.mutedForeground)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card Background

    @ViewBuilder
    private var cardBackground: some View {
        if #available(iOS 26.0, *) {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.3))
                .mementoGlassEffect(.regular, in: RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                .fill(colorScheme == .dark ? GrayScale.gray800 : GrayScale.gray100)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.lg, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
        }
    }

    // MARK: - Formatted Date

    private var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(session.createdAt) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInYesterday(session.createdAt) {
            return "Yesterday"
        } else if calendar.isDate(session.createdAt, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE" // Day name
        } else if calendar.isDate(session.createdAt, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }

        return formatter.string(from: session.createdAt)
    }
}

// MARK: - Previews

#Preview("Chat History Item") {
    VStack(spacing: 12) {
        ChatHistoryItem(
            session: ChatSession(
                title: "What patterns do you see in my recent journal entries?",
                createdAt: Date().addingTimeInterval(-3600 * 2)
            ),
            onTap: {}
        )

        ChatHistoryItem(
            session: ChatSession(
                title: "Help me understand my stress triggers from last week",
                createdAt: Date().addingTimeInterval(-86400)
            ),
            onTap: {}
        )

        ChatHistoryItem(
            session: ChatSession(
                title: "Summarize my mood patterns over the past month",
                createdAt: Date().addingTimeInterval(-86400 * 7)
            ),
            onTap: {}
        )
    }
    .padding()
    .useTheme()
    .useTypography()
}
