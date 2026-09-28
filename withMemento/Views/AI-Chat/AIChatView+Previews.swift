//
//  AIChatView+Previews.swift
//  withMemento
//
//  Canvas seeds for `AIChatView`, and the footer-height preference key they
//  share with it. Split out of `AIChatView.swift` so that file stays inside
//  SwiftLint's 700-line limit; nothing here is reachable outside previews
//  except `ChatFooterHeightKey`, which the chat scaffold reads.
//

import SwiftUI

/// Read by `AIChatView`'s scaffold, so it cannot be `private` now that it lives
/// in a separate file.
struct ChatFooterHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("Empty State") {
    @Previewable @StateObject var viewModel = ChatViewModel()
    NavigationStack {
        AIChatView(
            viewModel: viewModel,
            isEmbedded: true,
            hasEntries: true,
            seededSuggestions: ChatSuggestion.previewSamples
        )
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
        AIChatView(
            viewModel: viewModel,
            isEmbedded: true,
            hasEntries: true,
            seededSuggestions: ChatSuggestion.previewSamples
        )
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
    var isLoading: Bool = false
    var messages: [ChatMessage] = []

    // periphery:ignore - read only by #Preview canvases
    static var sampleTurn: [ChatMessage] {
        [
            ChatMessage(
                content: "What have I been writing about lately?",
                isFromUser: true
            ),
            ChatMessage(
                content: "You’ve been circling work pressure and how evenings feel shorter "
                    + "than they used to. A few entries come back to wanting more quiet, "
                    + "not more advice.",
                isFromUser: false
            )
        ]
    }
}

// periphery:ignore - instantiated only by #Preview canvases
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

// MARK: - Free tier previews (spec 021 R4, Figma 1177:3147)

// periphery:ignore - instantiated only by the #Preview canvases below
/// QA canvas for the free chat: Upgrade pill and reset in the header, no
/// starter tiles, and the daily-limit note. The allowance lives in its own
/// throwaway defaults suite, so previews never touch the real daily count.
private struct FreeChatPreview: View {
    var messages: [ChatMessage] = []
    var limitReached = false

    @StateObject private var viewModel: ChatViewModel

    init(messages: [ChatMessage] = [], limitReached: Bool = false) {
        self.messages = messages
        self.limitReached = limitReached
        let suite = "FreeChatPreview"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        // A limit of 1 with one message recorded reads as "used up", so the
        // view's own `refreshDailyLimit()` keeps the note up.
        let allowance = FreeChatAllowance(defaults: defaults, limitProvider: { 1 })
        if limitReached { allowance.recordMessage() }
        _viewModel = StateObject(wrappedValue: ChatViewModel(allowance: allowance))
    }

    var body: some View {
        NavigationStack {
            AIChatView(viewModel: viewModel, tier: .free, isEmbedded: true, hasEntries: true)
        }
        .useTheme()
        .useTypography()
        .onAppear {
            viewModel.messages = messages
            viewModel.dailyLimitReached = limitReached
        }
    }
}

#Preview("Free · Empty") {
    FreeChatPreview()
}

#Preview("Free · Dark") {
    FreeChatPreview()
        .preferredColorScheme(.dark)
}

#Preview("Free · Conversation") {
    FreeChatPreview(messages: AIChatNarrationPreviewConfiguration.sampleTurn)
}

#Preview("Free · Daily limit") {
    FreeChatPreview(messages: AIChatNarrationPreviewConfiguration.sampleTurn, limitReached: true)
}

#Preview("Free · AX5") {
    FreeChatPreview()
        .dynamicTypeSize(.accessibility5)
}
