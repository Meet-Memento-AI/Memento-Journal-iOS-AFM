//
//  LearnAboutYourselfView.swift
//  MeetMemento
//
//  Onboarding view for collecting initial journal entry about user goals.
//  Styled to match the journalreation experience (AddEntryView).
//

import SwiftUI

public struct LearnAboutYourselfView: View {
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @EnvironmentObject var appState: AppStateStore
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel

    // Use @ObservedObject for singleton to avoid creating duplicate observers
    @ObservedObject private var speechService = SpeechService.shared

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "LearnAboutYourselfView"

    @State private var entryText: String = ""
    @State private var showSTTError = false
    @State private var showPermissionDenied = false
    /// Guards against double-insert when both stop and final-transcript observers fire.
    @State private var didConsumeTranscript = false
    @FocusState private var isFocused: Bool

    // Callback for when user completes this step
    public var onComplete: ((String) -> Void)?
    public var isFirstStep: Bool = false
    public var onBack: (() -> Void)?

    public init(onComplete: ((String) -> Void)? = nil, isFirstStep: Bool = false, onBack: (() -> Void)? = nil) {
        self.onComplete = onComplete
        self.isFirstStep = isFirstStep
        self.onBack = onBack
    }

    public var body: some View {
        OnboardingPageScaffold(
            onBack: onBack,
            scrolls: true,
            trailing: {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    completeStep()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(theme.primary))
                }
                .accessibilityLabel("Continue")
                .accessibilityHint("Double-tap to save and continue")
                .accessibilityIdentifier("onboarding.continueLearn")
            },
            content: {
                VStack(alignment: .leading, spacing: OnboardingLayout.sectionSpacing) {
                    titleSection
                    bodyField
                }
            },
            footer: {
                HStack {
                    Spacer(minLength: 0)
                    microphoneFAB
                    Spacer(minLength: 0)
                }
            }
        )
        .onAppear {
            // Auto-focus the text editor after a brief delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                isFocused = true
            }
        }
        .onChange(of: speechService.isRecording) { oldValue, newValue in
            // Only process if this view owns the session
            guard speechService.isOwner(speechOwnerId) else { return }
            if newValue == true {
                didConsumeTranscript = false
            } else if oldValue == true && !speechService.isProcessing {
                consumeTranscriptOnce(speechService.bestAvailableTranscript)
            }
        }
        .onChange(of: speechService.transcribedText) { _, newText in
            // Only process if this view owns the session
            guard speechService.isOwner(speechOwnerId) else { return }
            if !newText.isEmpty && !speechService.isRecording {
                consumeTranscriptOnce(newText)
            }
        }
        .onChange(of: speechService.isProcessing) { _, processing in
            guard speechService.isOwner(speechOwnerId) else { return }
            if !processing && !speechService.isRecording {
                consumeTranscriptOnce(speechService.bestAvailableTranscript)
            }
        }
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
                        try await speechService.startRecording(ownerId: speechOwnerId)
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

    // MARK: - Subviews

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: OnboardingLayout.fieldSpacing) {
            Text("What would you like to learn about yourself?")
                .font(type.h3)
                .foregroundStyle(theme.foreground)
        }
    }

    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if entryText.isEmpty {
                Text("Share what your goals are with your journals. I'll pay attention to this whenever you journal and we talk.")
                    .font(type.body1)
                    .lineSpacing(3.4)
                    .foregroundStyle(theme.mutedForeground.opacity(0.5))
                    .padding(.top, OnboardingLayout.fieldSpacing)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $entryText)
                .font(type.body1)
                .lineSpacing(3.4)
                .foregroundStyle(theme.foreground)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
        }
    }

    // MARK: - Computed Properties

    private var fabWidth: CGFloat {
        speechService.isRecording ? 96 : 48
    }

    // MARK: - Actions

    private func completeStep() {
        let trimmedText = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        onComplete?(trimmedText)
    }

    private func consumeTranscriptOnce(_ transcribedText: String) {
        guard !didConsumeTranscript else { return }
        let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        didConsumeTranscript = true
        insertTranscribedText(trimmed)
    }

    private func insertTranscribedText(_ transcribedText: String) {
        if entryText.isEmpty {
            entryText = transcribedText
        } else {
            entryText += "\n\n" + transcribedText
        }
        // Clear transcription buffer and release ownership
        speechService.clearTranscription()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isFocused = true
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Microphone FAB

    private var microphoneFAB: some View {
        Button {
            // Provide haptic feedback for button tap
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            Task {
                if speechService.isRecording {
                    await speechService.stopRecording()
                } else {
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
            }
        } label: {
            HStack(spacing: OnboardingLayout.fieldSpacing) {
                Image(systemName: speechService.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(speechService.isRecording ? Color.red : theme.foreground)

                // Duration timer appears inside button when recording
                if speechService.isRecording {
                    Text(formatDuration(speechService.currentDuration))
                        .font(type.body2Bold)
                        .foregroundStyle(theme.destructive)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            // AX5: minHeight lets the pill grow instead of clipping the duration
            // timer text, which scales with Dynamic Type, when recording.
            .frame(minWidth: fabWidth, maxWidth: fabWidth, minHeight: 48)
            .background(microphoneFABBackground)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: speechService.isRecording)
        .accessibilityLabel(speechService.isRecording ? "Stop recording" : "Start voice recording")
        .accessibilityHint(speechService.isRecording ? "Double-tap to stop and insert text" : "Double-tap to record your voice")
    }

    @ViewBuilder
    private var microphoneFABBackground: some View {
        // Liquid Glass removed — flat themed surface — cardBackground adapts to dark mode.
        Capsule()
            .fill(theme.cardBackground)
    }
}

// MARK: - Previews

#Preview("Light") {
    LearnAboutYourselfView()
        .useTheme()
        .useTypography()
        .environmentObject(AppStateStore())
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    LearnAboutYourselfView()
        .useTheme()
        .useTypography()
        .environmentObject(AppStateStore())
        .environmentObject(OnboardingViewModel())
        .preferredColorScheme(.dark)
}

#Preview("With Content") {
    LearnAboutYourselfView()
        .useTheme()
        .useTypography()
        .environmentObject(AppStateStore())
        .environmentObject(OnboardingViewModel())
}
