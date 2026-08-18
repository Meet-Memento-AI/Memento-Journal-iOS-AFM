//
//  EditAboutYourselfView.swift
//  MeetMemento
//
//  Post-onboarding view for editing user's "about yourself" text.
//  Based on LearnAboutYourselfView but with pre-populated data and save functionality.
//

import SwiftUI

public struct EditAboutYourselfView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // Use @ObservedObject for singleton to avoid creating duplicate observers
    @ObservedObject private var speechService = SpeechService.shared

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "EditAboutYourselfView"

    @State private var entryText: String = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showSTTError = false
    @State private var showPermissionDenied = false
    @State private var showSaveSuccess = false
    @State private var rebuildError: String?
    /// Guards against double-insert when both stop and final-transcript observers fire.
    @State private var didConsumeTranscript = false
    @FocusState private var isFocused: Bool

    public init() {}

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom header with back button and save
                headerSection

                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.foreground))
                    Spacer()
                } else {
                    // Content area
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // Title section
                            titleSection
                                .padding(.top, 8)

                            // Body editor
                            bodyField
                                .padding(.top, 16)

                            // Character count indicator
                            characterCounter
                                .padding(.top, 12)

                            Spacer(minLength: 120)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if !isLoading {
                microphoneFAB
                    .padding(.bottom, 32)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            loadExistingText()
        }
        .onChange(of: speechService.isRecording) { oldValue, newValue in
            guard speechService.isOwner(speechOwnerId) else { return }
            if newValue == true {
                didConsumeTranscript = false
            } else if oldValue == true && !speechService.isProcessing {
                consumeTranscriptOnce(speechService.bestAvailableTranscript)
            }
        }
        .onChange(of: speechService.transcribedText) { _, newText in
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
        .alert("Couldn't update tuning", isPresented: .init(
            get: { rebuildError != nil },
            set: { if !$0 { rebuildError = nil } }
        )) {
            Button("OK") { rebuildError = nil }
        } message: {
            Text(rebuildError ?? "Your reflection was saved. Theme tuning can be rebuilt later in Settings.")
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        HStack(alignment: .center) {
            // Back button
            IconButtonNav(
                icon: "chevron.left",
                iconSize: 20,
                buttonSize: 40,
                foregroundColor: theme.foreground,
                useDarkBackground: false,
                enableHaptic: true,
                onTap: { dismiss() }
            )
            .accessibilityLabel("Back")

            Spacer()

            // Save button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                saveChanges()
            } label: {
                if isSaving {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.primaryForeground))
                        .frame(width: 60, height: 40)
                        .background(theme.primary)
                        .clipShape(Capsule())
                } else {
                    Text("Save")
                        .font(type.body2Bold)
                        .foregroundStyle(canSave ? theme.primaryForeground : theme.mutedForeground)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(canSave ? theme.primary : theme.muted)
                        .clipShape(Capsule())
                }
            }
            .disabled(!canSave || isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About yourself")
                .font(type.h3)
                .foregroundStyle(theme.foreground)

            Text("Update what you'd like to learn about yourself through journaling. Saving rebuilds how Memento quietly tunes chat to you.")
                .font(type.body2)
                .lineSpacing(3)
                .foregroundStyle(theme.mutedForeground)
        }
    }

    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if entryText.isEmpty {
                Text("Share what your goals are with your journals. I'll pay attention to this whenever you journal and we talk.")
                    .font(type.body1)
                    .lineSpacing(3.4)
                    .foregroundStyle(theme.mutedForeground.opacity(0.5))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $entryText)
                .font(type.body1)
                .lineSpacing(3.4)
                .foregroundStyle(theme.foreground)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 300)
        }
    }

    private var characterCounter: some View {
        HStack {
            Spacer()
            Text("\(characterCount) / 100 min")
                .font(type.caption)
                .foregroundStyle(
                    characterCount >= 100 ? theme.accent :
                    theme.mutedForeground.opacity(0.6)
                )
        }
    }

    // MARK: - Computed Properties

    private var characterCount: Int {
        entryText.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var canSave: Bool {
        characterCount >= 100
    }

    private var fabWidth: CGFloat {
        speechService.isRecording ? 96 : 48
    }

    // MARK: - Actions

    // No accounts (spec 023) — reads/writes the same local store onboarding
    // uses, not the old backend-service layer.
    private func loadExistingText() {
        entryText = LocalProfileStore.personalizationText ?? ""
        isLoading = false
    }

    private func saveChanges() {
        let trimmedText = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count >= 100 else { return }

        isSaving = true
        Task {
            // Persist reflection first, then rebuild lens while keeping confirmed themes.
            LocalProfileStore.personalizationText = trimmedText
            do {
                _ = try await ExperienceProfileBuilder.rebuildLens(
                    replaceConfirmedWithSuggestions: false
                )
                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    // Reflection is already saved; stay here so the alert can be read.
                    // User can dismiss manually after acknowledging.
                    rebuildError = error.localizedDescription
                    isSaving = false
                }
            }
        }
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
            HStack(spacing: 8) {
                Image(systemName: speechService.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(speechService.isRecording ? Color.red : theme.foreground)

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

#Preview("EditAboutYourselfView • Light") {
    NavigationStack {
        EditAboutYourselfView()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.light)
}

#Preview("EditAboutYourselfView • Dark") {
    NavigationStack {
        EditAboutYourselfView()
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
