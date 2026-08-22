//
//  ChatMessageBubble.swift
//  MeetMemento
//
//  Message bubble component for AI Chat interface
//

import SwiftUI

public struct ChatMessageBubble: View {
    let message: ChatMessage
    var animate: Bool
    /// True while the assistant reply is still streaming — forwarded to the
    /// typewriter so it only completes once the full reply has arrived.
    var isStreaming: Bool
    var feedbackType: FeedbackType?
    /// True while this message is the one being read aloud (spec 018 R7, chat
    /// amendment). Forwarded into AIOutputComponent's action bar.
    var isSpeaking: Bool
    /// True while this message's playback is paused (tap resumes).
    var isPaused: Bool
    var onCitationsTapped: (() -> Void)?
    var onSpeak: (() -> Void)?
    var onRedo: (() -> Void)?
    var onThumbsUp: (() -> Void)?
    var onThumbsDown: (() -> Void)?
    /// spec-010: tapped when a failed-to-send user message's retry row is tapped.
    var onRetry: (() -> Void)?
    /// Forwarded from AIOutputComponent when the reply finishes typing.
    var onAnimationComplete: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(
        message: ChatMessage,
        animate: Bool = true,
        isStreaming: Bool = false,
        feedbackType: FeedbackType? = nil,
        isSpeaking: Bool = false,
        isPaused: Bool = false,
        onCitationsTapped: (() -> Void)? = nil,
        onSpeak: (() -> Void)? = nil,
        onRedo: (() -> Void)? = nil,
        onThumbsUp: (() -> Void)? = nil,
        onThumbsDown: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onAnimationComplete: (() -> Void)? = nil
    ) {
        self.message = message
        self.animate = animate
        self.isStreaming = isStreaming
        self.feedbackType = feedbackType
        self.isSpeaking = isSpeaking
        self.isPaused = isPaused
        self.onCitationsTapped = onCitationsTapped
        self.onSpeak = onSpeak
        self.onRedo = onRedo
        self.onThumbsUp = onThumbsUp
        self.onThumbsDown = onThumbsDown
        self.onRetry = onRetry
        self.onAnimationComplete = onAnimationComplete
    }

    public var body: some View {
        if message.isFromUser {
            // User messages: right-aligned with bubble background
            HStack(alignment: .top, spacing: UserBubbleSurface.rowSpacing) {
                Spacer(minLength: UserBubbleSurface.leadingGutter)

                VStack(alignment: .trailing, spacing: 4) {
                    // Shared with the send choreography's flying ghost so the
                    // two cannot drift apart — see `UserBubbleSurface`.
                    UserBubbleSurface(text: message.content, imageJPEGs: message.imageJPEGs)

                    if message.sendFailed {
                        retryRow
                    }
                }
            }
        } else {
            // AI messages: full-width, no background container (Claude/ChatGPT style)
            messageContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }    
    // MARK: - Message Content
    
    /// Assistant-side content only. The user branch renders `UserBubbleSurface`
    /// directly in `body` so the send choreography's ghost can share it.
    @ViewBuilder
    private var messageContent: some View {
        if message.safetyPresentation == .crisisResource {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(type.body1)
                        .foregroundStyle(theme.foreground)
                        .lineSpacing(type.bodyLineSpacing)
                }
                CrisisResourceCard()
            }
        } else if message.safetyPresentation == .hardRefuse {
            // Authored refusal copy only — no typewriter, citations, or feedback
            // actions (regenerating a hard refuse is not a meaningful affordance).
            Text(message.content)
                .font(type.body1)
                .foregroundStyle(theme.foreground)
                .lineSpacing(type.bodyLineSpacing)
        } else if let aiContent = message.aiOutputContent, !isEmptyStreamingPlaceholder(aiContent) {
            // AI messages with structured content (headings, body, citations)
            AIOutputComponent(
                content: aiContent,
                animate: animate,
                isStreaming: isStreaming,
                feedbackType: feedbackType,
                isSpeaking: isSpeaking,
                isPaused: isPaused,
                onCitationsTapped: onCitationsTapped,
                onSpeak: onSpeak,
                onRedo: onRedo,
                onThumbsUp: onThumbsUp,
                onThumbsDown: onThumbsDown,
                onAnimationComplete: onAnimationComplete
            )
        } else {
            // AI messages: support markdown/rich text (fallback)
            // Clean any JSON artifacts that might have leaked through
            let cleanContent = cleanJSONFromContent(message.content)
            if cleanContent.isEmpty {
                // The pre-stream placeholder lands here once the branch above
                // rejects it. Render nothing — an empty Text still claims a
                // line's height, which is the gap above the loading indicator.
                EmptyView()
            } else {
                Text(LocalizedStringKey(cleanContent))
                    .font(type.body1)
                    .foregroundStyle(theme.foreground)
                    .lineSpacing(type.bodyLineSpacing)
            }
        }
    }

    /// True for the empty assistant bubble `ChatViewModel.performSend` appends
    /// the instant a prompt is sent, before any token has streamed back.
    ///
    /// Rendering a response shell for it puts padding — and, before this,
    /// a visible action bar — directly above the "Memento is thinking"
    /// indicator. `AILoadingState` already communicates that state, so the
    /// placeholder should occupy no space at all until it has content.
    private func isEmptyStreamingPlaceholder(_ content: AIOutputContent) -> Bool {
        content.body.isEmpty
            && (content.heading1 ?? "").isEmpty
            && (content.heading2 ?? "").isEmpty
            // Citations arrive on the very first delta for a grounded turn, before
            // any body text — mounting the component then lets "Reviewed your
            // journals" be the first thing to appear rather than waiting for text.
            && (content.citations?.isEmpty ?? true)
    }

    // MARK: - Retry Row

    private var retryRow: some View {
        Button {
            onRetry?()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .bold)) // icon-size: not user text
                Text("Failed to send · Retry")
                    .font(type.caption)
            }
            .foregroundStyle(theme.destructive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Message failed to send")
        .accessibilityHint("Double-tap to retry sending this message")
    }

    // MARK: - JSON Cleanup

    /// Extracts body text from content if it looks like JSON
    private func cleanJSONFromContent(_ content: String) -> String {
        // If content looks like JSON, try to extract body
        if content.hasPrefix("{") && content.contains("\"body\"") {
            if let data = content.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let body = json["body"] as? String {
                return body
            }
        }
        return content
    }
}

// MARK: - Previews

#Preview("User Message") {
    ChatMessageBubble(
        message: ChatMessage(
            content: "Enter an AI user input here. This will be used as part of component design",
            isFromUser: true
        )
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("AI Message") {
    ChatMessageBubble(
        message: ChatMessage(
            content: "Users can keep submitting responses here and engage directly with the AI.",
            isFromUser: false
        )
    )
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("AI Message with Markdown") {
    ChatMessageBubble(
        message: ChatMessage(
            content: "This is **bold text** and this is *italic text*. You can also include `code` snippets.",
            isFromUser: false
        )
    )
    .padding()
    .useTheme()
    .useTypography()
}
