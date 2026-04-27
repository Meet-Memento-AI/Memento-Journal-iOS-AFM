//
//  AddEntryView.swift
//  MeetMemento
//
//  Notion-style full-page journal entry editor with title and body fields.
//

import SwiftUI

// MARK: - Entry State

public enum EntryState: Hashable {
    case create                                          // Regular journal entry
    case createWithTitle(String)                         // Create with pre-filled title
    case createWithContent(title: String, content: String) // Create with pre-filled title and content (e.g., from chat summary)
    case edit(Entry)                                     // Editing existing entry
}

public struct AddEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    // Use @ObservedObject for singleton to avoid creating duplicate observers
    @ObservedObject private var speechService = SpeechService.shared

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "AddEntryView"

    @StateObject private var keyboardObserver = KeyboardObserver()

    @State private var title: String
    @State private var text: String
    @State private var isSaving = false
    @State private var showSTTError = false
    @State private var showPermissionDenied = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case title
        case body
    }

    let state: EntryState
    let onSave: (_ title: String, _ text: String) -> Void

    public init(
        state: EntryState,
        onSave: @escaping (_ title: String, _ text: String) -> Void
    ) {
        self.state = state
        self.onSave = onSave

        // Initialize title and text based on state
        switch state {
        case .create:
            _title = State(initialValue: "")
            _text = State(initialValue: "")
        case .createWithTitle(let prefillTitle):
            _title = State(initialValue: prefillTitle)
            _text = State(initialValue: "")
        case .createWithContent(let prefillTitle, let prefillContent):
            _title = State(initialValue: prefillTitle)
            _text = State(initialValue: prefillContent)
        case .edit(let entry):
            _title = State(initialValue: entry.title)
            _text = State(initialValue: entry.text)
        }
    }

    // MARK: - Computed Properties

    private var editingEntry: Entry? {
        if case .edit(let entry) = state { return entry }
        return nil
    }

    private var fabWidth: CGFloat {
        speechService.isRecording ? 96 : 48
    }

    private func keyboardBottomPadding(geometry: GeometryProxy) -> CGFloat {
        if keyboardObserver.isKeyboardVisible {
            let safeArea = geometry.safeAreaInsets.bottom
            return max(keyboardObserver.keyboardHeight - safeArea, 0) + 8
        } else {
            return 32
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Notion-style title field
                    titleField
                        .padding(.top, 24)

                    // Spacious body editor
                    bodyField
                        .padding(.top, 16)

                    Spacer(minLength: 100) // Space for FAB when keyboard hidden
                }
                .padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                microphoneFAB
                    .padding(.bottom, keyboardBottomPadding(geometry: geometry))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveButton
            }
        }
        .onAppear {
            setupInitialFocus()
        }
        .onChange(of: speechService.isRecording) { oldValue, newValue in
            // When recording stops, insert if we already have final text
            // Only process if this view owns the session
            guard speechService.isOwner(speechOwnerId) else { return }
            if oldValue == true && newValue == false && !speechService.transcribedText.isEmpty {
                insertTranscribedText(speechService.transcribedText)
            }
        }
        .onChange(of: speechService.transcribedText) { _, newText in
            // Final transcription arrives asynchronously after stop; insert when it appears and we're not recording
            // Only process if this view owns the session
            guard speechService.isOwner(speechOwnerId) else { return }
            if !newText.isEmpty && !speechService.isRecording {
                insertTranscribedText(newText)
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

    private var titleField: some View {
        TextField("", text: $title, axis: .vertical)
            .font(type.h3)
            .foregroundStyle(theme.foreground)
            .focused($focusedField, equals: .title)
            .textInputAutocapitalization(.words)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .body
            }
            .placeholder(when: title.isEmpty) {
                Text("Add a title...")
                    .font(type.h3)
                    .foregroundStyle(theme.mutedForeground.opacity(0.4))
            }
    }
    
    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Write your thoughts...")
                    .font(type.body1)
                    .lineSpacing(type.bodyLineSpacing)
                    .foregroundStyle(theme.mutedForeground.opacity(0.5))
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $text)
                .font(type.body1)
                .lineSpacing(type.bodyLineSpacing)
                .foregroundStyle(theme.foreground)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 300)
        }
    }
    
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
            HStack(spacing: 8) {
                Image(systemName: speechService.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(speechService.isRecording ? Color.red : theme.foreground)

                // Duration timer appears inside button when recording
                if speechService.isRecording {
                    Text(formatDuration(speechService.currentDuration))
                        .font(type.body2Bold)
                        .foregroundStyle(theme.destructive)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .frame(width: fabWidth, height: 48)
            .background(microphoneFABBackground)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: speechService.isRecording)
        .accessibilityLabel(speechService.isRecording ? "Stop recording" : "Start voice recording")
        .accessibilityHint(speechService.isRecording ? "Double-tap to stop and insert text" : "Double-tap to record your voice")
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            if isSaving {
                ProgressView()
                    .tint(theme.primary)
            } else {
                Image(systemName: "checkmark")
                    .font(type.body1Bold)
            }
        }
        .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private var microphoneFABBackground: some View {
        if #available(iOS 26.0, *) {
            // iOS 26: Liquid glass with frosted effect
            Capsule()
                .fill(Color.white.opacity(0.3))
                .mementoGlassEffect(.regular.interactive(), in: Capsule())
        } else {
            // iOS 18+: Ultra thin material fallback
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Actions

    private func setupInitialFocus() {
        // Focus immediately for instant writing experience
        // Focus title if empty, otherwise focus body
        focusedField = title.isEmpty ? .title : .body
    }

    private func save() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else { return }

        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        onSave(trimmedTitle, trimmedText)

        isSaving = false
    }

    private func insertTranscribedText(_ transcribedText: String) {
        // Append to body field with proper spacing
        if text.isEmpty {
            text = transcribedText
        } else {
            text += "\n\n" + transcribedText
        }

        // Clear transcription buffer and release ownership
        speechService.clearTranscription()

        // Provide haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Keep body field focused
        focusedField = .body
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Previews

#Preview("Create Entry") {
    NavigationStack {
        AddEntryView(state: .create) { _, _ in }
    }
    .useTheme()
    .useTypography()
}

#Preview("Edit Entry") {
    NavigationStack {
        AddEntryView(state: .edit(Entry.sampleEntries[0])) { _, _ in }
    }
    .useTheme()
    .useTypography()
}

#Preview("Create Entry • Dark") {
    NavigationStack {
        AddEntryView(state: .create) { _, _ in }
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
