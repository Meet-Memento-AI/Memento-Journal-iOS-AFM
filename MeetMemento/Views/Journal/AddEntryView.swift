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

    private var formattedDate: String {
        let date = editingEntry?.createdAt ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        let dayString = formatter.string(from: date)

        // Add ordinal suffix
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        switch day {
        case 1, 21, 31: suffix = "st"
        case 2, 22: suffix = "nd"
        case 3, 23: suffix = "rd"
        default: suffix = "th"
        }

        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        let year = yearFormatter.string(from: date)

        return "\(dayString)\(suffix), \(year)"
    }

    public var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Custom sheet header
                sheetHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Notion-style title field
                        titleField
                            .padding(.top, 16)

                        // Spacious body editor
                        bodyField
                            .padding(.top, 16)

                        Spacer(minLength: 100) // Space for FAB when keyboard hidden
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .overlay(alignment: .bottom) {
                microphoneFAB
                    .padding(.bottom, keyboardBottomPadding(geometry: geometry))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(theme.background.ignoresSafeArea())
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

    private var sheetHeader: some View {
        VStack(spacing: 12) {
            // Drag handle indicator
            Capsule()
                .fill(theme.border)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Header row
            HStack {
                // Back button
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.foreground)
                        .frame(width: 44, height: 44)
                        .background(iconButtonBackground)
                }

                Spacer()

                // Date pill
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .bold))
                    Text(formattedDate)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(datePillBackground)

                Spacer()

                // Submit button
                Button { save() } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(width: 44, height: 44)
                            .background(submitButtonBackground)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(submitButtonBackground)
                    }
                }
                .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Button Backgrounds

    @ViewBuilder
    private var iconButtonBackground: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Circle())
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        } else {
            fallbackIconButtonBackground
        }
        #else
        fallbackIconButtonBackground
        #endif
    }

    @ViewBuilder
    private var fallbackIconButtonBackground: some View {
        Circle()
            .fill(.thinMaterial)
            .overlay(Circle().strokeBorder(theme.glassBorder, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private var datePillBackground: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Capsule())
                .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        } else {
            fallbackDatePillBackground
        }
        #else
        fallbackDatePillBackground
        #endif
    }

    @ViewBuilder
    private var fallbackDatePillBackground: some View {
        Capsule()
            .fill(.thinMaterial)
            .overlay(Capsule().strokeBorder(theme.glassBorder, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private var submitButtonBackground: some View {
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let baseColor = isEmpty ? theme.primary.opacity(0.4) : theme.primary

        ZStack {
            Circle().fill(baseColor)
            // Glassy sheen overlay
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.25), Color.white.opacity(0.05), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        }
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

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
                Text("Journal title")
                    .font(type.h3)
                    .foregroundStyle(theme.mutedForeground.opacity(0.4))
            }
    }
    
    private var bodyField: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Write your entry here, or speak below to share what you're thinking & feeling...")
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(speechService.isRecording ? Color.red : theme.foreground)

                // Duration timer appears inside button when recording
                if speechService.isRecording {
                    Text(formatDuration(speechService.currentDuration))
                        .font(type.body1Bold)
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

    @ViewBuilder
    private var microphoneFABBackground: some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            // iOS 26: Liquid glass with frosted effect
            Capsule()
                .fill(Color.white.opacity(0.3))
                .mementoGlassEffect(.regular.interactive(), in: Capsule())
        } else {
            fallbackMicrophoneFABBackground
        }
        #else
        fallbackMicrophoneFABBackground
        #endif
    }

    @ViewBuilder
    private var fallbackMicrophoneFABBackground: some View {
        // iOS 18+: Ultra thin material fallback
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
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
    AddEntryView(state: .create) { _, _ in }
        .useTheme()
        .useTypography()
}

#Preview("Edit Entry") {
    AddEntryView(state: .edit(Entry.sampleEntries[0])) { _, _ in }
        .useTheme()
        .useTypography()
}

#Preview("Create Entry • Dark") {
    AddEntryView(state: .create) { _, _ in }
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Sheet Presentation") {
    Color.gray.opacity(0.3)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AddEntryView(state: .create) { _, _ in }
                .presentationDetents([.fraction(0.95)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(32)
        }
        .useTheme()
        .useTypography()
}
