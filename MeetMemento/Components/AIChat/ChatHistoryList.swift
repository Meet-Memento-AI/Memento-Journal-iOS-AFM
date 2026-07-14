//
//  ChatHistoryList.swift
//  MeetMemento
//
//  Scrollable list of chat history items
//

import SwiftUI

public struct ChatHistoryList: View {
    let sessions: [ChatSession]
    let onSessionSelect: (ChatSession) -> Void
    let onDelete: ((ChatSession) -> Void)?

    @Environment(\.theme) private var theme

    public init(
        sessions: [ChatSession],
        onSessionSelect: @escaping (ChatSession) -> Void,
        onDelete: ((ChatSession) -> Void)? = nil
    ) {
        self.sessions = sessions
        self.onSessionSelect = onSessionSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        if sessions.isEmpty {
            emptyState
        } else {
            List {
                ForEach(sessions) { session in
                    ChatHistoryItem(session: session) {
                        onSessionSelect(session)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 24, bottom: 6, trailing: 24))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        if onDelete != nil {
                            Button(role: .destructive) {
                                onDelete?(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(theme.mutedForeground.opacity(0.5))

            Text("No chat history yet")
                .font(.headline)
                .foregroundStyle(theme.mutedForeground)

            Text("Start a conversation to see it here")
                .font(.subheadline)
                .foregroundStyle(theme.mutedForeground.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Previews

#Preview("Chat History List") {
    ChatHistoryList(
        sessions: ChatSession.mockSessions,
        onSessionSelect: { session in
            AppLogger.log("[ChatHistory] Session selected")
        }
    )
    .useTheme()
    .useTypography()
}

#Preview("Empty State") {
    ChatHistoryList(
        sessions: [],
        onSessionSelect: { _ in }
    )
    .useTheme()
    .useTypography()
}
