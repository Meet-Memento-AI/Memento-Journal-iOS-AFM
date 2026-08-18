//
//  AIChatView.swift
//  MeetMemento
//
//  Chat page: typing and hands-free narration are modes of the same surface.
//  Header, thread, and scroll chrome stay put; the footer (and glow) swap.
//

import SwiftUI
import UIKit

public struct AIChatView: View {
    /// When true, the view renders its own header and is hosted by the pager.
    var isEmbedded: Bool = false
    /// Page back to the Journal screen. The header's book icon and a right
    /// swipe are the same navigation, so both route through here.
    var onOpenJournal: (() -> Void)? = nil
    /// Present the entry editor when embedded, matching `JournalView`. Chat has
    /// no `EntryViewModel` of its own, so a chat summary is handed to
    /// ContentView — the one place that actually persists an entry.
    var onPresentEntry: ((EntryRoute) -> Void)? = nil

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var narrationCoordinator = NarrationCoordinator()
    @ObservedObject private var speechService = SpeechService.shared
    @ObservedObject private var voiceService = VoicePlaybackService.shared
    @ObservedObject private var preferences = PreferencesService.shared
    @StateObject private var keyboardObserver = KeyboardObserver()

    private struct CitationsWrapper: Identifiable {
        let id = UUID()
        let citations: [JournalCitation]
    }

    @State private var isNarrating = false
    /// Compact-voice tip (spec 029 R8): shown when narration starts with a
    /// compact voice; the X persists dismissal so it never reappears.
    @State private var showVoiceNudge = false
    @State private var selectedCitations: CitationsWrapper? = nil
    /// Measured footer height (composer or narration stack), excluding the
    /// scaffold's `windowBottom + 16` pad.
    @State private var footerHeight: CGFloat = 80
    @State private var showChatHistorySheet = false
    @State private var showSummarySheet = false
    @State private var summaryError: String?
    @State private var currentSuggestions: [String] = []

    private let hasEntries: Bool
    /// When set, the view opens already in Narration Mode with this phase —
    /// used by canvas previews so QA does not have to start the mic.
    private let narrationPreview: AIChatNarrationPreviewConfiguration?

    private static var allPrompts: [String] = {
        if let url = Bundle.main.url(forResource: "AISuggestionPrompts", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let json = try? JSONDecoder().decode(PromptsFile.self, from: data) {
            return json.prompts
        }
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

    init(
        viewModel: ChatViewModel,
        isEmbedded: Bool = false,
        hasEntries: Bool = true,
        onOpenJournal: (() -> Void)? = nil,
        onPresentEntry: ((EntryRoute) -> Void)? = nil,
        narrationPreview: AIChatNarrationPreviewConfiguration? = nil
    ) {
        self.viewModel = viewModel
        self.isEmbedded = isEmbedded
        self.hasEntries = hasEntries
        self.onOpenJournal = onOpenJournal
        self.onPresentEntry = onPresentEntry
        self.narrationPreview = narrationPreview
        _isNarrating = State(initialValue: narrationPreview != nil)
        _showVoiceNudge = State(initialValue: narrationPreview?.showVoiceNudge ?? false)
    }

    private var footerBottomPadding: CGFloat {
        guard preferences.aiEnabled else { return 0 }
        if isNarrating { return AppHeaderMetrics.rowBottomPadding }
        return keyboardBottomPadding
    }

    private var bottomReserve: CGFloat {
        footerHeight + AppHeaderMetrics.windowBottom + footerBottomPadding + 8
    }

    private var keyboardBottomPadding: CGFloat {
        if keyboardObserver.isKeyboardVisible {
            return max(keyboardObserver.keyboardHeight - AppHeaderMetrics.windowBottom, 0)
        }
        return AppHeaderMetrics.rowBottomPadding
    }

    private var followTail: Bool {
        isNarrating && (narrationCoordinator.phase == .awaitingResponse
            || narrationCoordinator.phase == .speaking)
    }

    public var body: some View {
        RootPageScaffold(
            footerBottomPadding: footerBottomPadding,
            header: { if isEmbedded { chatHeader } },
            footer: { chatFooter },
            backgroundOverlay: {
                NarrationGlow(
                    isActive: isNarrating,
                    audioLevel: speechService.audioLevel,
                    isAutonomous: narrationCoordinator.phase == .speaking
                        || narrationCoordinator.phase == .awaitingResponse
                )
            }
        ) {
            ZStack {
                if preferences.aiEnabled {
                    ChatMessagesView(
                        viewModel: viewModel,
                        voiceService: voiceService,
                        hasEntries: hasEntries,
                        bottomReserve: bottomReserve,
                        followTail: followTail,
                        isKeyboardVisible: keyboardObserver.isKeyboardVisible,
                        onCitations: { selectedCitations = CitationsWrapper(citations: $0) },
                        onDismissKeyboard: dismissKeyboard
                    )

                    if keyboardObserver.isKeyboardVisible && !isNarrating {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { dismissKeyboard() }
                            .accessibilityHidden(true)
                    }

                    if showVoiceNudge && isNarrating {
                        voiceNudgeBanner
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, AppHeaderMetrics.contentTopPadding)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                } else {
                    aiDisabledView
                }
            }
        }
        .onPreferenceChange(ChatFooterHeightKey.self) { height in
            guard height > 0 else { return }
            footerHeight = height
        }
        .onAppear(perform: applyNarrationPreviewIfNeeded)
        .ignoresSafeArea(.keyboard)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            stopNarration()
            viewModel.cancelActiveTasks()
            viewModel.markAllMessagesSeen()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background { stopNarration() }
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
        .alert("Summary Failed", isPresented: .init(
            get: { summaryError != nil },
            set: { if !$0 { summaryError = nil } }
        )) {
            Button("OK") { summaryError = nil }
        } message: {
            Text(summaryError ?? "Unable to generate summary. Please try again.")
        }
        .alert("Something went wrong", isPresented: $viewModel.showingError) {
            Button("Retry") { viewModel.retrySend() }
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Please try again.")
        }
        .alert(
            "Microphone Access Required",
            isPresented: Binding(
                get: { narrationCoordinator.errorKind == .permissionDenied },
                set: { if !$0 { narrationCoordinator.errorKind = nil } }
            )
        ) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                stopNarration()
            }
            Button("Cancel", role: .cancel) { stopNarration() }
        } message: {
            Text(
                "MeetMemento needs microphone access to transcribe your voice. "
                + "Enable it in Settings > Privacy > Microphone."
            )
        }
        .alert(
            "Recording Failed",
            isPresented: Binding(
                get: { narrationCoordinator.errorKind == .recordingFailed },
                set: { if !$0 { narrationCoordinator.errorKind = nil } }
            )
        ) {
            Button("Try Again") { narrationCoordinator.retryListening() }
            Button("Cancel", role: .cancel) { stopNarration() }
        } message: {
            Text(speechService.errorMessage ?? "Unable to start recording. Please try again.")
        }
        .onAppear {
            // Launch → chat interactive marker (spec 029 R1/R5); Instruments
            // measures from process start to this point of interest.
            PerfSignposts.appLoad.emitEvent("chat.appeared")
            viewModel.prewarm()
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
            if isEmpty { rotateSuggestions() }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        AppHeader {
            HeaderIconButton(
                systemName: "book",
                accessibilityLabel: "Journal",
                accessibilityHint: "Double-tap to go back to your journal, or swipe right"
            ) {
                dismissKeyboard()
                onOpenJournal?()
            }
        } trailing: {
            HStack(spacing: 12) {
                HeaderIconButton(
                    systemName: "sparkles",
                    accessibilityLabel: "Summarise chat",
                    accessibilityHint: "Double-tap to turn this conversation into a journal entry"
                ) {
                    stopNarration()
                    dismissKeyboard()
                    showSummarySheet = true
                }
                HeaderIconButton(
                    systemName: "list.bullet",
                    accessibilityLabel: "Chat history"
                ) {
                    stopNarration()
                    showChatHistorySheet = true
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var chatFooter: some View {
        if preferences.aiEnabled {
            ZStack(alignment: .bottom) {
                AIChatFooter(
                    inputText: $viewModel.inputText,
                    isSending: viewModel.isLoading,
                    onSend: { viewModel.sendMessage() },
                    onNarrate: startNarration
                )
                .opacity(isNarrating ? 0 : 1)
                .allowsHitTesting(!isNarrating)
                .accessibilityHidden(isNarrating)

                NarrationFooter(
                    coordinator: narrationCoordinator,
                    onExit: stopNarration
                )
                .opacity(isNarrating ? 1 : 0)
                .allowsHitTesting(isNarrating)
                .accessibilityHidden(!isNarrating)
            }
            .animation(.easeInOut(duration: NarrationGlow.dissolveDuration), value: isNarrating)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChatFooterHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
        }
    }

    /// One-time compact-voice tip (spec 029 R8). Informational, non-blocking;
    /// the X persists dismissal via PreferencesService.
    private var voiceNudgeBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.mutedForeground)
                .padding(.top, 2)
            Text("A more natural voice is available — download an Enhanced voice in Settings → Voice.")
                .font(type.body2)
                .foregroundStyle(theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                preferences.compactVoiceNudgeDismissed = true
                withAnimation(.easeInOut(duration: 0.25)) { showVoiceNudge = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.mutedForeground)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("Dismiss voice tip")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.card)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        )
        .rootEdgeInset()
    }

    private var aiDisabledView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 56))
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
                    .foregroundStyle(theme.primaryForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, AppHeaderMetrics.contentTopPadding)
    }

    // MARK: - Narration

    private func applyNarrationPreviewIfNeeded() {
        guard let preview = narrationPreview else { return }
        isNarrating = true
        showVoiceNudge = preview.showVoiceNudge
        narrationCoordinator.seedPreview(
            phase: preview.phase,
            liveTranscript: preview.liveTranscript
        )
        viewModel.isLoading = preview.isLoading
        if !preview.messages.isEmpty {
            viewModel.messages = preview.messages
        }
    }

    private func startNarration() {
        dismissKeyboard()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: NarrationGlow.dissolveDuration)) {
            isNarrating = true
        }
        // One-time compact-voice tip (spec 029 R8): narration is about to
        // speak with a robotic compact voice and a better one is a download
        // away. Reads the warmed cache only — never triggers the slow
        // catalog enumeration.
        if !preferences.compactVoiceNudgeDismissed,
           let quality = voiceService.resolvedVoiceQuality,
           quality != .enhanced, quality != .premium {
            showVoiceNudge = true
        }
        Task { await voiceService.warmVoiceCatalog() }
        narrationCoordinator.start(chatViewModel: viewModel)
    }

    private func stopNarration() {
        guard isNarrating else {
            narrationCoordinator.stop()
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        narrationCoordinator.stop()
        withAnimation(.easeInOut(duration: NarrationGlow.dissolveDuration)) {
            isNarrating = false
            // Hide without persisting: only the explicit X commits dismissal.
            showVoiceNudge = false
        }
    }

    private func rotateSuggestions() {
        currentSuggestions = ThemeAwareChatStarters.rotate(genericPool: Self.allPrompts, limit: 3)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func handleSummarize() {
        Task {
            do {
                let result = try await viewModel.generateChatSummary()
                await MainActor.run {
                    showSummarySheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onPresentEntry?(.createWithContent(
                            title: result.title,
                            content: result.content
                        ))
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

private struct ChatFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    }
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

#Preview("Narration · Listening") {
    AIChatNarrationPreview(
        configuration: AIChatNarrationPreviewConfiguration(phase: .listening)
    )
}

#Preview("Narration · Live transcript") {
    AIChatNarrationPreview(
        configuration: AIChatNarrationPreviewConfiguration(
            phase: .listening,
            liveTranscript: "I’ve been thinking about how last week felt heavier than I expected, especially around work."
        )
    )
}

#Preview("Narration · Thinking") {
    AIChatNarrationPreview(
        configuration: AIChatNarrationPreviewConfiguration(
            phase: .awaitingResponse,
            isLoading: true,
            messages: AIChatNarrationPreviewConfiguration.sampleTurn
        )
    )
}

#Preview("Narration · Speaking") {
    AIChatNarrationPreview(
        configuration: AIChatNarrationPreviewConfiguration(
            phase: .speaking,
            messages: AIChatNarrationPreviewConfiguration.sampleTurn
        )
    )
}

#Preview("Narration · Voice nudge") {
    AIChatNarrationPreview(
        configuration: AIChatNarrationPreviewConfiguration(
            phase: .listening,
            showVoiceNudge: true
        )
    )
}

#Preview("Narration · Dark") {
    AIChatNarrationPreview(
        configuration: AIChatNarrationPreviewConfiguration(
            phase: .listening,
            liveTranscript: "What have I been writing about lately?"
        )
    )
    .preferredColorScheme(.dark)
}

/// Canvas seed for Narration Mode. Does not arm the mic or TTS.
struct AIChatNarrationPreviewConfiguration {
    var phase: NarrationCoordinator.Phase = .listening
    var liveTranscript: String = ""
    var showVoiceNudge: Bool = false
    var isLoading: Bool = false
    var messages: [ChatMessage] = []

    static var sampleTurn: [ChatMessage] {
        [
            ChatMessage(
                content: "What have I been writing about lately?",
                isFromUser: true
            ),
            ChatMessage(
                content: "You’ve been circling work pressure and how evenings feel shorter than they used to. A few entries come back to wanting more quiet, not more advice.",
                isFromUser: false
            )
        ]
    }
}

private struct AIChatNarrationPreview: View {
    let configuration: AIChatNarrationPreviewConfiguration
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        AIChatView(
            viewModel: viewModel,
            isEmbedded: true,
            narrationPreview: configuration
        )
        .useTheme()
        .useTypography()
    }
}
