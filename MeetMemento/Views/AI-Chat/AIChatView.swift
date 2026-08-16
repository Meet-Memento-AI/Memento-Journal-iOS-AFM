//
//  AIChatView.swift
//  MeetMemento
//
//  AI Chat interface for conversing with journal insights AI
//

import SwiftUI

public struct AIChatView: View {
    /// When true, the view renders its own header and is hosted by the pager.
    var isEmbedded: Bool = false
    /// Page back to the Journal screen. The header's book icon and a right
    /// swipe are the same navigation, so both route through here.
    var onOpenJournal: (() -> Void)? = nil

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss
    // NOTE: no connectivity gating here — chat is on-device only and must never
    // gate on network state (NetworkMonitor was deleted in the pre-1.0 cleanup).
    // See the empty-state comment below (PRES-048 / REQ-INT-009).

    /// ViewModel passed from parent to persist across tab switches
    @ObservedObject var viewModel: ChatViewModel

    private struct CitationsWrapper: Identifiable {
        let id = UUID()
        let citations: [JournalCitation]

        init(citations: [JournalCitation]) {
            self.citations = citations
        }
    }
    @State private var selectedCitations: CitationsWrapper? = nil
    @State private var scrollTask: Task<Void, Never>?
    @State private var scrollProxy: ScrollViewProxy?

    /// Measured height of the composer, so the scroll view reserves exactly what
    /// the input actually occupies as it grows to five lines / larger Dynamic
    /// Type. Seeded with the resting height (64pt capsule + AIChatFooter's 16pt
    /// vertical padding) so the very first layout pass is already correct.
    @State private var composerHeight: CGFloat = 96
    /// Breathing room between the last message and the composer.
    private let composerGap: CGFloat = 8
    @StateObject private var keyboardObserver = KeyboardObserver()

    /// Owned here again: the trigger is this page's own header now, not a
    /// shared one that only ContentView could reach.
    @State private var showChatHistorySheet = false

    // Summary flow state
    @State private var showSummarySheet = false
    @State private var summaryError: String?

    private struct SummaryItem: Identifiable {
        let id = UUID()
        let title: String
        let content: String
    }
    @State private var summaryItem: SummaryItem?

    @ObservedObject private var preferences = PreferencesService.shared
    /// Read-aloud playback (spec 018 R7, chat amendment). Observed here — not
    /// inside the bubbles — because this view owns message identity, so it can
    /// derive per-message `isSpeaking` the same way it derives `feedbackType`.
    @ObservedObject private var voiceService = VoicePlaybackService.shared

    // Suggestion prompts loaded from JSON with inline fallback
    @State private var currentSuggestions: [String] = []
    private static var allPrompts: [String] = {
        if let url = Bundle.main.url(forResource: "AISuggestionPrompts", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONDecoder().decode(PromptsFile.self, from: data) {
            return json.prompts
        }
        // Fallback prompts if JSON not available
        return [
            "Analyze my current mindset from my journal activity in the past week",
            "Explore the themes from my journals about my friendships",
            "Summarize my journal entries in the last month",
            "What emotions have I been experiencing most frequently?",
            "Help me identify patterns in my daily routines",
            "What are the recurring themes in my recent reflections?",
            "How has my mood shifted over the past two weeks?",
            "What am I most grateful for based on my entries?",
            "Find moments of joy I've captured in my journals",
            "What challenges have I overcome recently?",
            "What goals have I been working toward?",
            "How do my weekday entries differ from weekend ones?",
            "What relationships seem most important to me right now?",
            "Identify any sources of stress I've mentioned recently",
            "What have I learned about myself this month?",
            "What brings me peace according to my entries?",
            "How do I handle difficult situations?",
            "What creative ideas have I been exploring?",
            "Suggest one intention for the week ahead based on my entries",
            "What does happiness mean to me based on my reflections?"
        ]
    }()

    private struct PromptsFile: Decodable {
        let prompts: [String]
    }

    /// Whether the journal has any entries. Every prompt in `allPrompts` asks
    /// about "my entries" / "my journals" / "the past week", so against an empty
    /// journal all of them fail — the model has nothing but
    /// "[No journal entries matched this topic]" to work from. On a cold install
    /// that is the first thing a reviewer taps. When false, the empty state
    /// invites a first entry instead of offering corpus questions.
    /// Defaults to true so previews and non-embedded call sites are unchanged.
    private let hasEntries: Bool

    init(
        viewModel: ChatViewModel,
        isEmbedded: Bool = false,
        hasEntries: Bool = true,
        onOpenJournal: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.isEmbedded = isEmbedded
        self.hasEntries = hasEntries
        self.onOpenJournal = onOpenJournal
    }

    /// Rotate suggestions: prefer ThemeCatalog-tuned starters, fall back to generic pool.
    private func rotateSuggestions() {
        currentSuggestions = ThemeAwareChatStarters.rotate(genericPool: Self.allPrompts, limit: 3)
    }
    
    /// Small breathing room under the header. The header itself reserves its
    /// own height via `safeAreaInset`, so this is no longer a hand-computed
    /// `safeAreaTop + 8 + 44 + 32` guess at another view's geometry.
    private let topContentInset: CGFloat = 16

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Full-screen background - must fill entire space including safe areas
                theme.background
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .all)

                if preferences.aiEnabled {
                    // Messages list - fills available space with bottom inset for input
                    messagesScrollView(bottomReserve: bottomReserve(geometry: geometry))
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            // Reserve the composer's MEASURED height, not a constant.
                            // This was hardcoded to 88 — correct only for a
                            // single-line composer at default type size. The field
                            // grows to five lines and scales with Dynamic Type, so
                            // a long draft slid underneath the last message.
                            Color.clear.frame(height: bottomReserve(geometry: geometry))
                        }
                        // The header reserves its own height, so nothing here
                        // hand-computes another view's geometry any more.
                        .safeAreaInset(edge: .top, spacing: 0) {
                            if isEmbedded { chatHeader }
                        }

                    // No scrim, in either mode. Typing never had one: the
                    // composer rising to meet the keyboard is enough of a mode
                    // change on its own, and frosting the conversation the
                    // moment someone starts typing hides the very messages they
                    // are replying to. Narrate used to get one because its 280pt
                    // panel took over the bottom of the screen and needed
                    // separating from the conversation behind it — dictation now
                    // renders inline in the 64pt capsule, so there is nothing
                    // left to separate. Removing it also drops a full-screen
                    // material composited over a live ScrollView, whose backdrop
                    // was re-sampled every frame of an interactive dismiss.

                    // Outside-tap target, present ONLY while the keyboard is up.
                    // Being conditional is what makes it safe: it cannot shadow
                    // message content at rest, and when it is up the first tap
                    // dismisses the keyboard while a second reaches whatever was
                    // tapped — the standard iOS convention. Sits above the list
                    // and below the composer so the send button stays live.
                    if keyboardObserver.isKeyboardVisible {
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture { dismissKeyboard() }
                            .accessibilityHidden(true)
                    }

                    // Bottom gradient fade for scroll content
                    // Positioned above messages, below floating input
                    VStack {
                        Spacer()
                        ScrollEdgeFade(edge: .bottom, height: 100)
                    }
                    .allowsHitTesting(false)

                    // Input area - floats at bottom with no background
                    VStack {
                        Spacer()
                        floatingInputArea
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ComposerHeightKey.self,
                                        value: proxy.size.height
                                    )
                                }
                            )
                            .padding(.bottom, keyboardBottomPadding(geometry: geometry))
                    }
                    .onPreferenceChange(ComposerHeightKey.self) { height in
                        guard height > 0 else { return }
                        composerHeight = height
                    }

                } else {
                    // AI Disabled State
                    aiDisabledView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .all)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .all)
        .ignoresSafeArea(.keyboard)
        .background(theme.background.ignoresSafeArea(edges: .all))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            scrollTask?.cancel()
            scrollTask = nil
            // spec-010: stop leaking in-flight send/feedback Tasks when the
            // view goes away, matching the existing scrollTask convention above.
            viewModel.cancelActiveTasks()
            // Already-animated messages shouldn't replay their typewriter
            // entrance when the user switches back to this tab.
            viewModel.markAllMessagesSeen()
        }
        .sheet(item: $selectedCitations) { wrapper in
            CitationsBottomSheet(citations: wrapper.citations)
        }
        .sheet(isPresented: $showChatHistorySheet) {
            ChatHistorySheet(
                sessions: viewModel.sessions,
                isLoading: viewModel.isLoadingSessions,
                onSessionSelect: { session in
                    Task { await viewModel.loadSession(session) }
                },
                onNewChat: {
                    withAnimation { viewModel.startNewChat() }
                },
                onDeleteSession: { session in
                    Task { await viewModel.deleteSession(session) }
                }
            )
        }
        .sheet(isPresented: $showSummarySheet) {
            ChatSummarySheet(
                onSummarize: { handleSummarize() },
                isSummarizing: viewModel.isSummarizing
            )
        }
        .sheet(item: $summaryItem) { item in
            AddEntryView(
                state: .createWithContent(title: item.title, content: item.content),
                // NOTE: pre-existing gap, not introduced/fixed here — this closure
                // never calls entryViewModel.createEntry, so chat-summary entries
                // may not persist today. Widened to compile; worth a separate look.
                onSave: { title, content, photoAction in
                    summaryItem = nil
                }
            )
            .presentationDetents([.fraction(0.95)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(32)
            .useTheme()
            .useTypography()
        }
        .alert("Summary Failed", isPresented: .init(
            get: { summaryError != nil },
            set: { if !$0 { summaryError = nil } }
        )) {
            Button("OK") { summaryError = nil }
        } message: {
            Text(summaryError ?? "Unable to generate summary. Please try again.")
        }
        .onAppear {
            // Warm the on-device model now so the first send is fast.
            viewModel.prewarm()
            // Initialize suggestions on first appear
            if currentSuggestions.isEmpty {
                rotateSuggestions()
            }
            Task {
                await viewModel.fetchSessions()
                if viewModel.userName == nil {
                    await viewModel.fetchUserName()
                }
            }
        }
        .onChange(of: viewModel.messages.isEmpty) { _, isEmpty in
            // Rotate suggestions when returning to empty state (new chat)
            if isEmpty {
                rotateSuggestions()
            }
        }
        .alert("Something went wrong", isPresented: $viewModel.showingError) {
            Button("Retry") { viewModel.retrySend() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
    }
    
    // MARK: - Header (Figma 483:1235)

    private var chatHeader: some View {
        AppHeader {
            // Top-left, facing its destination: Journal is the page to the
            // left, and a right swipe reveals it. The mirrored counterpart of
            // Journal's top-right chat icon.
            HeaderIconButton(
                systemName: "book",
                size: 48,
                accessibilityLabel: "Journal",
                accessibilityHint: "Double-tap to go back to your journal, or swipe right"
            ) {
                // Let go of the keyboard before the page moves, or it stays up
                // over the Journal screen.
                dismissKeyboard()
                onOpenJournal?()
            }
        } trailing: {
            // Shown unconditionally, as drawn. It used to be gated on having
            // sessions; the sheet already has an empty state, so the gate only
            // made the control flicker into existence after the first chat.
            HeaderIconButton(
                systemName: "list.bullet",
                size: 48,
                accessibilityLabel: "Chat history"
            ) {
                showChatHistorySheet = true
            }
        }
    }

    // MARK: - Messages Scroll View

    /// Space reserved under the transcript for the floating composer (and keyboard).
    /// Shared by the scroll inset and the empty-state vertical centering so the
    /// welcome block doesn't drift when the field grows or the keyboard rises.
    private func bottomReserve(geometry: GeometryProxy) -> CGFloat {
        composerHeight + composerGap + keyboardBottomPadding(geometry: geometry)
    }

    private func messagesScrollView(bottomReserve: CGFloat) -> some View {
        ScrollViewReader { proxy in
            GeometryReader { geo in
                if viewModel.messages.isEmpty && !viewModel.isLoading {
                    // Empty state: vertically centered in visible area (between header and input)
                    let visibleHeight = max(geo.size.height - topContentInset - bottomReserve, 0)

                    VStack {
                        // Chat runs entirely on-device via SystemLanguageModel and makes
                        // no network request, so connectivity is irrelevant here. The old
                        // "You're offline — Chat needs a connection" branch (spec-007 R3)
                        // described the deleted Supabase backend and was actively false:
                        // an App Review tester in airplane mode would be told the app's
                        // headline feature was unavailable while it worked perfectly.
                        //
                        // PRES-048 already scopes the offline empty state to Z1
                        // (Private Cloud Compute) with Z0 degradation per REQ-INT-009.
                        // No Z1 feature has shipped, so it applies to nothing today —
                        // re-introduce it against Z1 surfaces only, never against Z0.
                        emptyStateContent
                    }
                    .frame(width: geo.size.width, height: visibleHeight)
                    .padding(.top, topContentInset)
                    .id("empty")
                } else {
                    // Messages: scrollable content
                    ScrollView {
                        // Messages: start at top with padding
                        LazyVStack(alignment: .leading, spacing: 32) {
                            ForEach(viewModel.messages) { message in
                                ChatMessageBubble(
                                    message: message,
                                    animate: message.isNew,
                                    isStreaming: message.isStreaming,
                                    feedbackType: viewModel.feedbackType(for: message.id),
                                    isSpeaking: voiceService.speakingMessageID == message.id,
                                    isPaused: voiceService.speakingMessageID == message.id
                                        && voiceService.isPaused,
                                    onCitationsTapped: {
                                        if let citations = message.citations, !citations.isEmpty {
                                            selectedCitations = CitationsWrapper(citations: citations)
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
                                        // Regenerate removes the message pair —
                                        // speech must not outlive its message.
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
                                .id(message.id)
                            }

                            // Loading State Indicator
                            if viewModel.isLoading {
                                AILoadingState()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .id("loading-state")
                            }
                        }
                        .padding(16)
                        .padding(.top, topContentInset)
                        .padding(.bottom, 16)
                    }
                }
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: viewModel.messages.count) { oldCount, newCount in
                // Only scroll when messages are added (not removed)
                if newCount > oldCount, let lastMessage = viewModel.messages.last {
                    // Scroll the new message to the top of the visible area
                    scrollToUserMessage(proxy: proxy, messageId: lastMessage.id)
                }
            }
            .onChange(of: viewModel.isLoading) { _, newValue in
                if newValue {
                    // Keep user's message visible at top, loading indicator appears below
                    scrollTask?.cancel()
                    scrollTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        guard !Task.isCancelled else { return }
                        // Scroll to the last user message (the one just sent)
                        if let lastUserMessage = viewModel.messages.last(where: { $0.isFromUser }) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastUserMessage.id, anchor: .top)
                            }
                        }
                    }
                }
            }
            .onChange(of: keyboardObserver.isKeyboardVisible) { _, isVisible in
                if isVisible {
                    scrollToLatestMessage()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(theme.background)
            // Replaces the opaque `ScrollEdgeFade(.top)` that ContentView used to
            // paint behind the floating header, and `.hard` rather than `.soft`
            // so content is cut crisply at the bar instead of fading into a hazy
            // band under it — see YourEntriesView for the full reasoning.
            .scrollEdgeEffectStyle(.hard, for: .top)
            // ⚠️ This gesture spans the whole message list, and it will SWALLOW
            // taps from any descendant that is not a `Button`. A plain
            // `.onTapGesture` on a child loses to it across the ScrollView
            // boundary, and the child silently stops responding — that is
            // exactly how the citations modal broke once (CitationLink was
            // briefly reimplemented with `.onTapGesture` instead of `Button`).
            // Make tappable children `Button`s, or attach
            // `.highPriorityGesture` if a Button is genuinely unsuitable.
            .onTapGesture {
                dismissKeyboard()
            }
        }
    }
    
    private func scrollToUserMessage(proxy: ScrollViewProxy, messageId: UUID) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo(messageId, anchor: .top)
        }
    }


    // MARK: - Floating Input Area

    private var floatingInputArea: some View {
        AIChatFooter(
            inputText: $viewModel.inputText,
            isSending: viewModel.isLoading,
            onSend: { viewModel.sendMessage() }
        )
    }

    // MARK: - Empty State Content

    private var emptyStateContent: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 24) {
                // Memento icon — left 32/132 of logo SVG rendered at 44pt height
                Image("Memento-Logo")
                    .resizable()
                    .frame(width: 176, height: 44)
                    .frame(width: 44, alignment: .leading)
                    .clipped()

                // Welcome message
                Text("Let’s dive deeper into your journal")
                    .font(type.h2)
                    .foregroundStyle(theme.foreground)
                    .multilineTextAlignment(.center)
                    // The block sits in a fixed-height frame with a Spacer above
                    // and below, so the VStack is free to compress the headline
                    // rather than the Spacers — at h2 that truncated it to a
                    // single "Let's dive deeper into…". This claims the height
                    // the wrapped text actually needs.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)

                // NOTE: the suggested-prompt cards that used to sit here for
                // `hasEntries` are temporarily removed. `currentSuggestions` /
                // `rotateSuggestions()` are deliberately left in place — they
                // still run, they just have no renderer for now, so restoring
                // the strip is a matter of putting the ScrollView back.
                if !hasEntries {
                    // No entries yet: every suggestion in the pool asks about a
                    // corpus that does not exist, so offering them guarantees a
                    // poor first answer. Point at the actual first step instead.
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
    }

    // MARK: - AI Disabled View

    private var aiDisabledView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 56)) // icon-size: not user text
                .foregroundStyle(theme.mutedForeground.opacity(0.5))

            Text("AI Features Disabled")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("Enable AI features in Settings to use the chat assistant and get personalized insights.")
                .font(type.body1)
                .foregroundStyle(theme.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(action: {
                preferences.aiEnabled = true
            }) {
                Text("Enable AI Features")
                    .font(type.body1Bold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(theme.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, topContentInset)
    }

    // MARK: - Keyboard Padding Calculation

    private func keyboardBottomPadding(geometry: GeometryProxy) -> CGFloat {
        let homeIndicator = geometry.safeAreaInsets.bottom
        if keyboardObserver.isKeyboardVisible {
            // Keyboard is visible - position input above keyboard with 16px extra spacing.
            // Subtract the home-indicator inset because keyboardHeight is measured from
            // the screen bottom while this view ignores the safe area.
            return max(keyboardObserver.keyboardHeight - homeIndicator, 0) + 16
        } else {
            // Keyboard hidden — clear the home indicator, with at least 32pt of air.
            return max(32, homeIndicator + 8)
        }
    }

    // MARK: - Scroll Helpers

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

    // MARK: - Actions

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleSummarize() {
        Task {
            do {
                let result = try await viewModel.generateChatSummary()
                await MainActor.run {
                    showSummarySheet = false
                    // Small delay for sheet dismiss animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        summaryItem = SummaryItem(title: "Chat Reflection", content: result.content)
                    }
                }
            } catch {
                await MainActor.run {
                    showSummarySheet = false
                    summaryError = error.localizedDescription
                }
            }
        }
    }

}

// MARK: - Composer height

/// Reports the composer's rendered height up to `AIChatView`, so the message
/// list can reserve exactly the space the input occupies rather than a constant
/// that only held for a single line at default type size.
private struct ComposerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Previews

#Preview("Empty State") {
    @Previewable @StateObject var viewModel = ChatViewModel()
    NavigationStack {
        AIChatView(viewModel: viewModel)
    }
    .useTheme()
    .useTypography()
}

#Preview("With Messages") {
    @Previewable @StateObject var viewModel = ChatViewModel()
    NavigationStack {
        AIChatView(viewModel: viewModel)
            .onAppear {
                // Mock messages for preview
            }
    }
    .useTheme()
    .useTypography()
}

#Preview("Chat History Sheet") {
    ChatHistorySheet(
        sessions: ChatSession.mockSessions,
        onSessionSelect: { session in
            AppLogger.log("[ChatHistory] Session selected")
        },
        onNewChat: {
            AppLogger.log("New chat started")
        }
    )
    .useTheme()
    .useTypography()
}

#Preview("Dark Mode") {
    @Previewable @StateObject var viewModel = ChatViewModel()
    NavigationStack {
        AIChatView(viewModel: viewModel)
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
