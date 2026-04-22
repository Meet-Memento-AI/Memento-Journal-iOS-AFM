//
//  ChatHistorySheet.swift
//  MeetMemento
//
//  Bottom sheet showing past chat sessions
//

import SwiftUI

public struct ChatHistorySheet: View {
    let sessions: [ChatSession]
    let isLoading: Bool
    let onSessionSelect: (ChatSession) -> Void
    let onNewChat: () -> Void
    let onDeleteSession: ((ChatSession) -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss

    public init(
        sessions: [ChatSession],
        isLoading: Bool = false,
        onSessionSelect: @escaping (ChatSession) -> Void,
        onNewChat: @escaping () -> Void,
        onDeleteSession: ((ChatSession) -> Void)? = nil
    ) {
        self.sessions = sessions
        self.isLoading = isLoading
        self.onSessionSelect = onSessionSelect
        self.onNewChat = onNewChat
        self.onDeleteSession = onDeleteSession
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
                .fill(theme.mutedForeground.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)

            // Header with title and new chat button
            HStack {
                Text("Chat History")
                    .font(type.h5)
                    .foregroundStyle(theme.foreground)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                    onNewChat()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                        Text("New")
                            .font(type.body2Bold)
                    }
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(newButtonBackground)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 24)

            // Session list or empty/loading state
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.2)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if sessions.isEmpty {
                VStack(spacing: Spacing.md) {
                    Spacer()

                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundStyle(theme.mutedForeground)

                    Text("No conversations yet")
                        .font(type.h5)
                        .foregroundStyle(theme.foreground)

                    Text("Start a new chat to see your history here")
                        .font(type.body2)
                        .foregroundStyle(theme.mutedForeground)
                        .multilineTextAlignment(.center)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding(Spacing.xl)
            } else {
                ChatHistoryList(
                    sessions: sessions,
                    onSessionSelect: { session in
                        dismiss()
                        onSessionSelect(session)
                    },
                    onDelete: onDeleteSession
                )
            }
        }
        .background(theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - New Button Background

    @ViewBuilder
    private var newButtonBackground: some View {
        Capsule()
            .fill(theme.primary.opacity(0.1))
    }
}

// MARK: - Previews

#Preview("Chat History Sheet") {
    ChatHistorySheet(
        sessions: ChatSession.mockSessions,
        onSessionSelect: { session in
            print("Selected: \(session.title)")
        },
        onNewChat: {
            print("New chat")
        }
    )
    .useTheme()
    .useTypography()
}

#Preview("Empty History") {
    ChatHistorySheet(
        sessions: [],
        onSessionSelect: { _ in },
        onNewChat: {}
    )
    .useTheme()
    .useTypography()
}
