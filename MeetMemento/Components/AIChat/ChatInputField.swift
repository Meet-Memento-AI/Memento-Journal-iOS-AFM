//
//  ChatInputField.swift
//  MeetMemento
//
//  Expandable input component with 3 states:
//  - Default: Two buttons side by side (Chat + Voice CTA)
//  - Chat Active: Expanded text input with send button
//  - Narrate: Full listening panel
//

import SwiftUI

struct ChatInputField: View {
    // MARK: - Input State Enum

    enum InputState: Equatable {
        case defaultState       // Two buttons side by side
        case chatActive         // Expanded text input
        case narrateActive      // Listening panel
    }

    // MARK: - Properties

    @Binding var text: String
    var onSend: () -> Void
    /// Called when the input field should be dismissed (e.g., tap outside)
    var onDismiss: (() -> Void)?
    /// Called when the chat history button is tapped
    var onHistoryTap: (() -> Void)?
    /// Called when narrate state changes (true = active, false = inactive)
    var onNarrateStateChange: ((Bool) -> Void)?
    /// When false, input is disabled (e.g. carousel preview in WelcomeView)
    var isInteractive: Bool
    /// Whether there are existing chat sessions (shows history button when true)
    var hasExistingChats: Bool
    /// For preview purposes - allows setting initial state
    var initialState: InputState

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.colorScheme) private var colorScheme
    @State private var inputState: InputState
    @FocusState private var isFocused: Bool
    @ObservedObject private var speechService = SpeechService.shared
    @State private var showPermissionDenied = false
    @State private var showSTTError = false
    @State private var showListeningContent = false
    /// Ensures one voice utterance sends exactly once (both speech observers can
    /// fire for the same utterance). Reset when a new recording starts.
    @State private var didConsumeTranscript = false
    @Namespace private var animationNamespace

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "ChatInputField"

    // MARK: - Design Constants

    private let pillHeight: CGFloat = 48
    private let cornerRadius: CGFloat = 24
    private let listeningPanelHeight: CGFloat = 280
    private let sendButtonSize: CGFloat = 36
    private let backButtonSize: CGFloat = 48
    private let listeningButtonSize: CGFloat = 48

    // Note: Colors now use theme tokens for consistency

    /// Whether the input is in an expanded state (chatActive or narrateActive)
    var isExpanded: Bool {
        inputState == .chatActive || inputState == .narrateActive
    }

    // MARK: - Initializer

    init(
        text: Binding<String>,
        onSend: @escaping () -> Void = {},
        onDismiss: (() -> Void)? = nil,
        onHistoryTap: (() -> Void)? = nil,
        onNarrateStateChange: ((Bool) -> Void)? = nil,
        isInteractive: Bool = true,
        hasExistingChats: Bool = false,
        initialState: InputState = .defaultState
    ) {
        self._text = text
        self.onSend = onSend
        self.onDismiss = onDismiss
        self.onHistoryTap = onHistoryTap
        self.onNarrateStateChange = onNarrateStateChange
        self.isInteractive = isInteractive
        self.hasExistingChats = hasExistingChats
        self.initialState = initialState
        self._inputState = State(initialValue: initialState)
    }

    // MARK: - Body

    var body: some View {
        Group {
            switch inputState {
            case .defaultState:
                defaultView
                    .transition(.opacity)

            case .chatActive:
                chatActiveView
                    .transition(.opacity)

            case .narrateActive:
                narrateActiveView
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: inputState)
        .allowsHitTesting(isInteractive)
        // A single utterance can satisfy BOTH observers below (recording stops
        // with text present, then a final transcript lands). `consumeTranscriptOnce`
        // guards so exactly one send fires per recording session — the previous
        // code relied on the `!isLoading` guard racing, which was fragile.
        .onChange(of: speechService.isRecording) { oldValue, newValue in
            guard speechService.isOwner(speechOwnerId) else { return }
            if newValue == true {
                didConsumeTranscript = false            // new recording — arm one consume
            } else if oldValue == true {
                consumeTranscriptOnce(speechService.transcribedText)
            }
        }
        .onChange(of: speechService.transcribedText) { _, newText in
            guard speechService.isOwner(speechOwnerId) else { return }
            if !speechService.isRecording {              // final transcript after stop
                consumeTranscriptOnce(newText)
            }
        }
        .onChange(of: isFocused) { _, newValue in
            // Return to default state when focus is lost in chatActive state.
            // The draft is intentionally kept: dismissing the keyboard by
            // tapping or scrolling the conversation must not erase what the
            // user has typed — reopening the input restores it.
            if !newValue && inputState == .chatActive {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    inputState = .defaultState
                }
                onDismiss?()
            }
        }
        .modifier(SpeechAlertsModifier(
            showPermissionDenied: $showPermissionDenied,
            showSTTError: $showSTTError,
            speechService: speechService,
            ownerId: speechOwnerId
        ))
    }

    // MARK: - Dismiss Method (Public)

    /// Call this method to dismiss the input field and return to default state
    func dismiss() {
        if inputState == .chatActive {
            text = ""
            isFocused = false
        }
        inputState = .defaultState
        onDismiss?()
    }

    // MARK: - State 1: Default View

    private var defaultView: some View {
        HStack(spacing: 12) {
            // HISTORY PILL: Only shown when hasExistingChats
            if hasExistingChats {
                historyPill()
                    .transition(.scale.combined(with: .opacity))
            }

            // LEFT PILL: "Chat with Memento"
            leftPill()

            // RIGHT PILL: Voice button (starts listening directly)
            rightPill()
        }
    }

    // MARK: - Left Pill (Chat with Memento)

    @ViewBuilder
    private func leftPill() -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                inputState = .chatActive
            }
        } label: {
            HStack(spacing: 12) {
                Image("LaunchLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text("Chat with Memento")
                    .font(type.h6)
                    .foregroundStyle(theme.mutedForeground)
            }
            // AX5: minHeight lets the pill grow instead of clipping/overlapping
            // "Chat with Memento" when it scales up at large Dynamic Type sizes.
            .frame(minHeight: pillHeight)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .frame(minHeight: pillHeight)
        .background(
            glassBackground(cornerRadius: cornerRadius)
                .matchedGeometryEffect(id: "chatBackground", in: animationNamespace)
        )
        .contentShape(Rectangle())
        .accessibilityLabel("Chat with Memento")
    }

    // MARK: - Right Pill (Voice Button - starts listening directly)

    @ViewBuilder
    private func rightPill() -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            startListening()
        } label: {
            voiceWaveIcon(color: theme.foreground)
                .frame(height: pillHeight)
        }
        .buttonStyle(.plain)
        .frame(width: pillHeight, height: pillHeight)
        .background(
            glassBackground(cornerRadius: cornerRadius)
                .matchedGeometryEffect(id: "narrateBackground", in: animationNamespace)
        )
        .contentShape(Rectangle())
        .accessibilityLabel("Start voice narration")
    }

    // MARK: - History Icon

    private var historyIcon: some View {
        Image(systemName: "text.document")
            .font(.system(size: 18, weight: .bold)) // icon-size: not user text
            .foregroundStyle(theme.foreground)
    }

    // MARK: - History Pill (Chat History Button)

    @ViewBuilder
    private func historyPill() -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onHistoryTap?()
        } label: {
            historyIcon
                .frame(width: pillHeight, height: pillHeight)
        }
        .buttonStyle(.plain)
        .frame(width: pillHeight, height: pillHeight)
        .background(glassBackground(cornerRadius: cornerRadius))
        .contentShape(Rectangle())
        .accessibilityLabel("Chat history")
    }

    // MARK: - State 2: Chat Active View

    private var chatActiveView: some View {
        // Regular chat-bar layout: stays pill-height for a single line and
        // grows only as the text wraps (up to 5 lines), instead of jumping
        // to a tall composer panel the moment the pill is tapped.
        HStack(alignment: .bottom, spacing: 12) {
            TextField(
                "",
                text: $text,
                prompt: Text("Chat with Memento")
                    .foregroundStyle((colorScheme == .dark ? Color.white : Color.black).opacity(0.6)),
                axis: .vertical
            )
                .font(type.body1)
                .foregroundStyle(theme.foreground)
                .focused($isFocused)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                // Vertically centers a single line against the send button.
                .frame(minHeight: sendButtonSize)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold)) // icon-size: not user text
                    .foregroundColor(.white)
                    .frame(width: sendButtonSize, height: sendButtonSize)
                    .background(
                        Circle()
                            .fill(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  ? theme.primary.opacity(0.5)
                                  : theme.primary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        // AX5: minHeight (not a fixed height) so wrapped lines and large
        // Dynamic Type sizes grow the bar instead of clipping the input.
        .frame(minHeight: pillHeight)
        .frame(maxWidth: .infinity)
        .background(
            glassBackground(cornerRadius: cornerRadius)
                .matchedGeometryEffect(id: "chatBackground", in: animationNamespace)
        )
        .onAppear {
            isFocused = true
        }
    }

    // MARK: - State 4: Narrate Active View (Listening)

    private var narrateActiveView: some View {
        VStack(spacing: 0) {
            // Top row: Back + Done buttons
            HStack {
                // Back button with single chevron
                Button {
                    cancelListening()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(theme.primary)
                        .frame(width: listeningButtonSize, height: listeningButtonSize)
                        .background(
                            Circle()
                                .fill(PrimaryScale.primary50)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Cancel recording")
                .accessibilityHint("Double-tap to cancel and go back")

                Spacer()

                // Done button with checkmark
                Button {
                    confirmListening()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold)) // icon-size: not user text
                        .foregroundColor(.white)
                        .frame(width: listeningButtonSize, height: listeningButtonSize)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [PrimaryScale.primary600, PrimaryScale.primary800],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Confirm recording")
                .accessibilityHint("Double-tap to stop recording and send")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .opacity(showListeningContent ? 1 : 0)
            .scaleEffect(showListeningContent ? 1 : 0.8)

            Spacer()

            // Center: Animated wave bars
            ListeningDotsView(audioLevel: speechService.audioLevel)
                .opacity(showListeningContent ? 1 : 0)
                .scaleEffect(showListeningContent ? 1 : 0.5)

            Spacer()

            // Label
            Text("Narrate")
                .font(type.body1)
                .foregroundStyle(theme.primary)
                .padding(.bottom, 24)
                .opacity(showListeningContent ? 1 : 0)
        }
        .frame(height: listeningPanelHeight)
        .frame(maxWidth: .infinity)
        .background(
            glassBackground(cornerRadius: cornerRadius)
                .matchedGeometryEffect(id: "narrateBackground", in: animationNamespace)
        )
        .onAppear {
            // Delay content appearance until panel has expanded
            withAnimation(.easeOut(duration: 0.3).delay(0.15)) {
                showListeningContent = true
            }
        }
        .onDisappear {
            showListeningContent = false
        }
    }

    // MARK: - Voice Wave Icon

    private func voiceWaveIcon(color: Color) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Create a wave pattern: shorter on edges, taller in middle
        let heights: [CGFloat] = [8, 14, 18, 14, 8]
        return heights[index]
    }

    // MARK: - Glass Background

    @ViewBuilder
    private func glassBackground(cornerRadius: CGFloat) -> some View {
        // Liquid Glass removed — flat #fafafa surface (no shadow).
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(hex: "#FAFAFA"))
    }

    // MARK: - Speech Actions

    private func startListening() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Transition to listening panel
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            inputState = .narrateActive
        }
        onNarrateStateChange?(true)

        // Start recording
        Task {
            do {
                try await speechService.startRecording(ownerId: speechOwnerId)
            } catch let error as SpeechService.SpeechError {
                // Fade out and return to default on error
                onNarrateStateChange?(false)
                withAnimation(.easeOut(duration: 0.15)) {
                    showListeningContent = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        inputState = .defaultState
                    }
                }
                if case .permissionDenied = error {
                    showPermissionDenied = true
                } else {
                    showSTTError = true
                }
            } catch {
                onNarrateStateChange?(false)
                withAnimation(.easeOut(duration: 0.15)) {
                    showListeningContent = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        inputState = .defaultState
                    }
                }
                showSTTError = true
            }
        }
    }

    private func cancelListening() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onNarrateStateChange?(false)

        // Fade out content first
        withAnimation(.easeOut(duration: 0.15)) {
            showListeningContent = false
        }

        // Then transition panel after content fades
        Task {
            await speechService.stopRecording()
            speechService.clearTranscription()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                inputState = .defaultState
            }
        }
    }

    private func confirmListening() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onNarrateStateChange?(false)

        // Fade out content first
        withAnimation(.easeOut(duration: 0.15)) {
            showListeningContent = false
        }

        Task {
            await speechService.stopRecording()
            // Text will be inserted via onChange handler
            // But if transcription is empty after processing, we need to return to default
            // Wait a moment for transcription to be processed
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // If still in narrateActive and no transcription was processed, return to default
            await MainActor.run {
                if inputState == .narrateActive {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        inputState = .defaultState
                    }
                }
            }
        }
    }

    private func sendMessage() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSend()
        // Return to default state after sending
        text = ""
        inputState = .defaultState
        isFocused = false
    }

    /// Consume the transcript at most once per recording session, so the two
    /// speech observers can't both send it.
    private func consumeTranscriptOnce(_ transcribedText: String) {
        guard !didConsumeTranscript, !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        didConsumeTranscript = true
        insertTranscribedText(transcribedText)
    }

    private func insertTranscribedText(_ transcribedText: String) {
        let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Fade out content first, then transition
            onNarrateStateChange?(false)
            withAnimation(.easeOut(duration: 0.15)) {
                showListeningContent = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                inputState = .defaultState
            }
            return
        }

        if text.isEmpty {
            text = trimmed
        } else {
            text += "\n\n" + trimmed
        }

        // Clear transcription buffer and release ownership
        speechService.clearTranscription()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Send the message
        onSend()
        text = ""

        // Smooth transition back to default
        onNarrateStateChange?(false)
        withAnimation(.easeOut(duration: 0.15)) {
            showListeningContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            inputState = .defaultState
        }
    }
}

// MARK: - Speech Alerts Modifier

private struct SpeechAlertsModifier: ViewModifier {
    @Binding var showPermissionDenied: Bool
    @Binding var showSTTError: Bool
    let speechService: SpeechService
    let ownerId: String

    func body(content: Content) -> some View {
        content
            .alert("Microphone Access Required", isPresented: $showPermissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("MeetMemento needs microphone access to transcribe your voice. Enable it in Settings > Privacy > Microphone.")
            }
            .alert("Recording Failed", isPresented: $showSTTError) {
                Button("Try Again") {
                    Task {
                        do {
                            try await speechService.startRecording(ownerId: ownerId)
                        } catch {
                            showSTTError = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(speechService.errorMessage ?? "Unable to start recording. Please try again.")
            }
    }
}

// MARK: - Previews

#Preview("Default State") {
    VStack {
        Spacer()
        ChatInputField(text: .constant(""), onSend: {})
            .padding(.horizontal, 20)
    }
    .useTheme()
    .useTypography()
}

#Preview("Chat Active") {
    ChatInputFieldPreview(initialState: .chatActive)
        .useTheme()
        .useTypography()
}

#Preview("Narrate Active") {
    ChatInputFieldPreview(initialState: .narrateActive)
        .useTheme()
        .useTypography()
}

#Preview("Dark Mode - Default") {
    VStack {
        Spacer()
        ChatInputField(text: .constant(""), onSend: {})
            .padding(.horizontal, 20)
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}

#Preview("Dark Mode - Chat Active") {
    ChatInputFieldPreview(initialState: .chatActive)
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Interactive") {
    ChatInputFieldInteractivePreview()
        .useTheme()
        .useTypography()
}

#Preview("With Chat History") {
    VStack {
        Spacer()
        ChatInputField(
            text: .constant(""),
            onSend: {},
            onHistoryTap: { AppLogger.log("History tapped") },
            hasExistingChats: true
        )
        .padding(.horizontal, 20)
    }
    .useTheme()
    .useTypography()
}

#Preview("With Chat History - Dark Mode") {
    VStack {
        Spacer()
        ChatInputField(
            text: .constant(""),
            onSend: {},
            onHistoryTap: { AppLogger.log("History tapped") },
            hasExistingChats: true
        )
        .padding(.horizontal, 20)
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}

private struct ChatInputFieldPreview: View {
    let initialState: ChatInputField.InputState
    @State private var text = ""

    var body: some View {
        VStack {
            Spacer()
            ChatInputField(
                text: $text,
                onSend: { AppLogger.log("Send: \(text)") },
                initialState: initialState
            )
            .padding(.horizontal, 20)
        }
    }
}

private struct ChatInputFieldInteractivePreview: View {
    @State private var text = ""

    var body: some View {
        VStack {
            Spacer()

            Text("Tap buttons to navigate states")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            ChatInputField(
                text: $text,
                onSend: {
                    AppLogger.log("Sent: \(text)")
                    text = ""
                },
                onHistoryTap: {
                    AppLogger.log("History tapped")
                },
                hasExistingChats: true
            )
            .padding(.horizontal, 20)
        }
    }
}
