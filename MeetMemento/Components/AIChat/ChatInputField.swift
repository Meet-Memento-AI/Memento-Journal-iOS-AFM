//
//  ChatInputField.swift
//  MeetMemento
//
//  Input field component for AI Chat interface with send button
//  Matches Claude/ChatGPT style with send button positioned inside input field
//

import SwiftUI

public struct ChatInputField: View {
    @Binding var text: String
    var isSending: Bool
    var onSend: () -> Void
    /// When false, input and all buttons are disabled (e.g. carousel preview in WelcomeView).
    var isInteractive: Bool = true
    /// When true, shows the journal button to access chat history
    var hasChatHistory: Bool = false
    /// Callback when journal button is tapped
    var onJournalTap: (() -> Void)? = nil

    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool
    // Use @ObservedObject for singleton to avoid creating duplicate observers
    @ObservedObject private var speechService = SpeechService.shared
    @State private var showPermissionDenied = false
    @State private var showSTTError = false

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "ChatInputField"

    public init(
        text: Binding<String>,
        isSending: Bool = false,
        isInteractive: Bool = true,
        hasChatHistory: Bool = false,
        onSend: @escaping () -> Void,
        onJournalTap: (() -> Void)? = nil
    ) {
        self._text = text
        self.isSending = isSending
        self.isInteractive = isInteractive
        self.hasChatHistory = hasChatHistory
        self.onSend = onSend
        self.onJournalTap = onJournalTap
    }

    // MARK: - Computed Properties

    /// Determines if the journal button should be visible
    /// Hidden when user is actively typing (focused or has text) for a smoother experience
    private var shouldShowJournalButton: Bool {
        hasChatHistory && !isFocused && text.isEmpty
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: 12) {
            if shouldShowJournalButton {
                journalButton
                    .transition(.scale.combined(with: .opacity))
            }

            ZStack(alignment: .bottomTrailing) {
                textInput
                buttonRow
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: shouldShowJournalButton)
        .allowsHitTesting(isInteractive)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onChange(of: speechService.isRecording) { oldValue, newValue in
            // Only process if this view owns the session
            guard speechService.isOwner(speechOwnerId) else { return }
            if oldValue == true && newValue == false && !speechService.transcribedText.isEmpty {
                insertTranscribedText(speechService.transcribedText)
            }
        }
        .onChange(of: speechService.transcribedText) { _, newText in
            // Only process if this view owns the session
            guard speechService.isOwner(speechOwnerId) else { return }
            if !newText.isEmpty && !speechService.isRecording {
                insertTranscribedText(newText)
            }
        }
        .modifier(SpeechAlertsModifier(
            showPermissionDenied: $showPermissionDenied,
            showSTTError: $showSTTError,
            speechService: speechService,
            ownerId: speechOwnerId
        ))
    }

    // MARK: - Trailing Padding

    private var trailingPadding: CGFloat {
        text.isEmpty ? 100 : 52
    }

    // MARK: - Text Input

    private var textInput: some View {
        ZStack(alignment: .center) {
            if speechService.isRecording {
                VoiceWaveView(audioLevel: speechService.audioLevel)
                    .frame(height: 24)
                    .padding(.leading, 16)
                    .padding(.trailing, 56)
                    .padding(.vertical, 16)
                    .transition(.opacity)
            } else {
                defaultInputView
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(inputFieldBackground)
        .animation(.easeInOut(duration: 0.2), value: speechService.isRecording)
    }

    // MARK: - Input Field Background

    @ViewBuilder
    private var inputFieldBackground: some View {
        if #available(iOS 26.0, *) {
            // iOS 26: Liquid glass effect with higher frost (semi-transparent fill adds opacity)
            RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .mementoGlassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        } else {
            // iOS 18+: Light grey background
            RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous)
                .fill(theme.inputBackground)
        }
    }

    // MARK: - Default Input View

    private var defaultInputView: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Chat with Memento")
                    .typographyBody1()
                    .foregroundStyle(theme.mutedForeground)
                    .padding(.leading, 16)
                    .padding(.top, 16)
            }

            TextField("", text: $text, axis: .vertical)
                .typographyBody1()
                .foregroundStyle(theme.foreground)
                .focused($isFocused)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .disabled(!isInteractive)
                .onSubmit {
                    guard isInteractive, isSendButtonEnabled else { return }
                    onSend()
                }
                .padding(.leading, 16)
                .padding(.trailing, trailingPadding)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
        }
    }

    // MARK: - Button Row

    private var buttonRow: some View {
        HStack(spacing: 16) {
            if speechService.isRecording {
                stopButton
                    .transition(.scale.combined(with: .opacity))
            } else {
                if text.isEmpty {
                    microphoneButton
                        .transition(.scale.combined(with: .opacity))
                }
                sendButton
            }
        }
        .animation(.easeInOut(duration: 0.2), value: text.isEmpty)
        .padding(.trailing, 8)
        .padding(.bottom, 10)
    }
    
    // MARK: - Microphone Button
    
    private var microphoneButton: some View {
        Button {
            guard isInteractive else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                do {
                    try await speechService.startRecording(ownerId: speechOwnerId)
                } catch let error as SpeechService.SpeechError {
                    if case .permissionDenied = error {
                        showPermissionDenied = true
                    } else {
                        showSTTError = true
                    }
                } catch {
                    showSTTError = true
                }
            }
        } label: {
            Image(systemName: "mic")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.mutedForeground)
                .frame(width: 36, height: 36)
                .background(Color.clear)
        }
        .disabled(speechService.isProcessing)
        .accessibilityLabel("Start voice input")
        .accessibilityHint("Double-tap to record your voice")
    }
    
    // MARK: - Stop Button
    
    private var stopButton: some View {
        Button {
            guard isInteractive else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                await speechService.stopRecording()
            }
        } label: {
            Image(systemName: "square.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.red)
                )
        }
        .accessibilityLabel("Stop voice input")
        .accessibilityHint("Double-tap to stop and insert text")
    }

    // MARK: - Journal Button

    private var journalButton: some View {
        Button {
            guard isInteractive else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onJournalTap?()
        } label: {
            Image(systemName: "text.book.closed")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.mutedForeground)
                .frame(width: 44, height: 44)
                .background(journalButtonBackground)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat history")
        .accessibilityHint("Double-tap to view past conversations")
    }

    @ViewBuilder
    private var journalButtonBackground: some View {
        if #available(iOS 26.0, *) {
            Circle()
                .fill(Color.white.opacity(0.4))
                .mementoGlassEffect(.regular.interactive(), in: Circle())
        } else {
            Circle()
                .fill(theme.inputBackground)
        }
    }

    // MARK: - Send Button
    
    private var sendButton: some View {
        Button {
            guard isInteractive else { return }
            onSend()
        } label: {
            ZStack {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSendButtonEnabled ? .white : theme.mutedForeground)
                }
            }
            .frame(width: 36, height: 36)
            .background(
                Circle()
                    .fill(
                        isSendButtonEnabled
                            ? theme.primary
                            : theme.muted
                    )
            )
        }
        .disabled(!isInteractive || !isSendButtonEnabled || isSending)
        .animation(.easeInOut(duration: 0.2), value: isSendButtonEnabled)
        .accessibilityLabel(isSending ? "Sending message" : "Send message")
        .accessibilityHint("Double-tap to send")
    }

    private var isSendButtonEnabled: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func insertTranscribedText(_ transcribedText: String) {
        let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if text.isEmpty {
            text = trimmed
        } else {
            text += "\n\n" + trimmed
        }
        // Clear transcription buffer and release ownership
        speechService.clearTranscription()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSend()
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

// MARK: - Voice Wave View (voice-reactive)
private struct VoiceWaveView: View {
    let audioLevel: Float
    private let barCount = 30
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 20
    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 4

    private static func barVariation(for index: Int) -> CGFloat {
        let seed = sin(CGFloat(index) * 0.7) * 0.5 + 0.5
        return 0.7 + 0.3 * seed
    }

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: barWidth, height: barHeight(for: index))
                    .animation(.easeOut(duration: 0.12), value: audioLevel)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        let variation = Self.barVariation(for: index)
        let amplitude = (maxHeight - minHeight) * level * variation
        return max(minHeight, minHeight + amplitude)
    }
}

// MARK: - Previews

#Preview("Input Field - No History") {
    @Previewable @State var text = ""

    VStack {
        Spacer()
        ChatInputField(text: $text, onSend: {
            print("Send: \(text)")
        })
    }
    .useTheme()
    .useTypography()
}

#Preview("Input Field - With History") {
    @Previewable @State var text = ""

    VStack {
        Spacer()
        ChatInputField(
            text: $text,
            hasChatHistory: true,
            onSend: {
                print("Send: \(text)")
            },
            onJournalTap: {
                print("Journal tapped")
            }
        )
    }
    .useTheme()
    .useTypography()
}

#Preview("Input Field - Active Typing") {
    @Previewable @State var text = "What patterns do you see in my recent entries?"

    VStack {
        Spacer()
        Text("Journal button hidden while typing")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)
        // Note: Journal button is hidden when text is not empty or field is focused
        // This provides a smoother typing experience with full-width input
        ChatInputField(
            text: $text,
            hasChatHistory: true,
            onSend: {
                print("Send: \(text)")
            },
            onJournalTap: {
                print("Journal tapped")
            }
        )
    }
    .useTheme()
    .useTypography()
}

#Preview("Input Field Recording") {
    @Previewable @State var text = ""

    VStack {
        Spacer()
        // Note: Preview won't auto-trigger recording state unless we expose it,
        // but user can interact in preview
        ChatInputField(text: $text, onSend: {})
    }
    .useTheme()
    .useTypography()
}
