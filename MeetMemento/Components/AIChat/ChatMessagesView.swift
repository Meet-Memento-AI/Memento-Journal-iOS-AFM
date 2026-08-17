//
//  ChatMessagesView.swift
//  MeetMemento
//
//  Shared thread for Chat's typing and narration modes: empty state, bubbles,
//  loading row, header clearance, and footer reserve.
//

import Combine
import SwiftUI

struct ChatMessagesView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var voiceService: VoicePlaybackService
    var hasEntries: Bool
    var bottomReserve: CGFloat
    var followTail: Bool
    var isKeyboardVisible: Bool
    var onCitations: ([JournalCitation]) -> Void
    var onDismissKeyboard: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    @State private var scrollTask: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?

    private let followClock = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    private static let bottomAnchorID = "chat-transcript-end"

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if viewModel.messages.isEmpty && !viewModel.isLoading {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id("empty")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 32) {
                            ForEach(viewModel.messages) { message in
                                bubble(for: message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                AILoadingState()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .id("loading-state")
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(Self.bottomAnchorID)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, AppHeaderMetrics.contentTopPadding)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: bottomReserve)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                if newCount > oldCount, let lastMessage = viewModel.messages.last {
                    scrollToUserMessage(proxy: proxy, messageId: lastMessage.id)
                }
            }
            .onChange(of: viewModel.isLoading) { _, newValue in
                if newValue {
                    scrollTask?.cancel()
                    scrollTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard !Task.isCancelled else { return }
                        if let lastUserMessage = viewModel.messages.last(where: { $0.isFromUser }) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastUserMessage.id, anchor: .top)
                            }
                        }
                    }
                }
            }
            .onChange(of: isKeyboardVisible) { _, isVisible in
                if isVisible { scrollToLatestMessage() }
            }
            .onReceive(followClock) { _ in
                guard followTail else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onDisappear {
                scrollTask?.cancel()
                scrollTask = nil
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(.clear)
            .scrollEdgeEffectHidden(true, for: .top)
            // ⚠️ This gesture spans the whole message list, and it will SWALLOW
            // taps from any descendant that is not a `Button`. A plain
            // `.onTapGesture` on a child loses to it across the ScrollView
            // boundary, and the child silently stops responding — that is
            // exactly how the citations modal broke once (CitationLink was
            // briefly reimplemented with `.onTapGesture` instead of `Button`).
            .onTapGesture {
                onDismissKeyboard()
            }
        }
    }

    private func bubble(for message: ChatMessage) -> some View {
        ChatMessageBubble(
            message: message,
            animate: message.isNew,
            isStreaming: message.isStreaming,
            feedbackType: viewModel.feedbackType(for: message.id),
            isSpeaking: voiceService.speakingMessageID == message.id,
            isPaused: voiceService.speakingMessageID == message.id && voiceService.isPaused,
            onCitationsTapped: {
                if let citations = message.citations, !citations.isEmpty {
                    onCitations(citations)
                }
            },
            onSpeak: message.isFromUser ? nil : {
                if let ai = message.aiOutputContent {
                    voiceService.toggleSpeech(
                        messageID: message.id,
                        heading1: ai.heading1,
                        heading2: ai.heading2,
                        body: ai.body
                    )
                }
            },
            onRedo: message.isFromUser ? nil : {
                voiceService.stopIfSpeaking(messageID: message.id)
                viewModel.regenerateResponse(for: message.id)
            },
            onThumbsUp: message.isFromUser ? nil : {
                viewModel.toggleThumbsUp(for: message.id)
            },
            onThumbsDown: message.isFromUser ? nil : {
                viewModel.toggleThumbsDown(for: message.id)
            },
            onRetry: message.isFromUser ? { viewModel.retryMessage(message) } : nil,
            onAnimationComplete: { viewModel.markMessageSeen(message.id) }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                Image("Memento-Logo")
                    .resizable()
                    .frame(width: 176, height: 44)
                    .frame(width: 44, alignment: .leading)
                    .clipped()

                Text("Let’s dive deeper into your journal")
                    .font(type.h2)
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)

                if !hasEntries {
                    Text("Write a journal entry first — then I can reflect it back to you, and show you which entries I drew from.")
                        .font(type.body1)
                        .foregroundStyle(theme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
        }
        .padding(.top, AppHeaderMetrics.contentTopPadding)
    }

    private func scrollToUserMessage(proxy: ScrollViewProxy, messageId: UUID) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(messageId, anchor: .top)
        }
    }

    private func scrollToLatestMessage() {
        guard let proxy = scrollProxy else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                if let lastMessage = viewModel.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .top)
                } else if viewModel.isLoading {
                    proxy.scrollTo("loading-state", anchor: .top)
                }
            }
        }
    }
}
