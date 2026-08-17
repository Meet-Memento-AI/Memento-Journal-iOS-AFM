//
//  AddEntryView.swift
//  MeetMemento
//
//  Notion-style full-page journal entry editor with title and body fields.
//

import SwiftUI
import PhotosUI
import AVFoundation

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
    /// Home-indicator inset cached while the keyboard is hidden — same reason
    /// as `AIChatView.restingHomeIndicator`: live `safeAreaInsets.bottom` is
    /// usually 0 in this sheet's GeometryReader (or becomes the keyboard), so
    /// subtracting it left the FABs floating well above the keys.
    @State private var restingHomeIndicator: CGFloat = 0

    @State private var title: String
    @State private var text: String
    @State private var isSaving = false
    @State private var showSTTError = false
    @State private var showPermissionDenied = false
    /// Guards against double-insert when both stop and final-transcript observers fire.
    @State private var didConsumeTranscript = false

    // MARK: Photo state
    @State private var photoData: Data?
    @State private var photoPreviewImage: UIImage?
    /// False until the user actually touches the photo this session — lets
    /// `.edit(entry)` preselect an existing photo without `save()` treating
    /// that preselection itself as a change.
    @State private var photoDidChange = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showCameraCapture = false
    @State private var showCameraUnavailable = false
    @State private var showCameraPermissionDenied = false

    @FocusState private var focusedField: Field?

    enum Field: Hashable {
        case title
        case body
    }

    let state: EntryState
    let onSave: (_ title: String, _ text: String, _ photoAction: PhotoAction) -> Void

    public init(
        state: EntryState,
        onSave: @escaping (_ title: String, _ text: String, _ photoAction: PhotoAction) -> Void
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

    /// What to report to `onSave` — computed from the session's photo state,
    /// not diffed against `Data`, since the explicit `photoDidChange` flag is
    /// cheap and unambiguous (see `PhotoAction`'s doc comment).
    private var photoAction: PhotoAction {
        guard photoDidChange else { return .unchanged }
        if let photoData { return .set(photoData) }
        return .removed
    }

    /// 56pt idle matches Figma's trailing FAB (and the attachment pill's
    /// height); it expands to fit the duration timer while recording.
    private var fabWidth: CGFloat {
        speechService.isRecording ? 112 : 56
    }

    private func keyboardBottomPadding(geometry: GeometryProxy) -> CGFloat {
        guard keyboardObserver.isKeyboardVisible else {
            // Resting: FABs sit on the sheet's bottom frame edge (16pt air,
            // matching `PositionedNewEntryFAB.edgeInset` / chat composer).
            return PositionedNewEntryFAB.edgeInset
        }

        let home = restingHomeIndicator > 0
            ? restingHomeIndicator
            : max(geometry.safeAreaInsets.bottom, Self.windowBottomSafeArea())
        // Flush to the keyboard — no extra +8 gap.
        return max(keyboardObserver.keyboardHeight - home, 0)
    }

    private static func windowBottomSafeArea() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.bottom ?? 0
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
                        // Live WYSIWYG preview of the cover photo — mirrors
                        // exactly what the saved JournalCard will show.
                        if let photoPreviewImage {
                            JournalPhotoThumbnail(
                                image: Image(uiImage: photoPreviewImage),
                                removable: true,
                                onRemove: {
                                    self.photoData = nil
                                    self.photoPreviewImage = nil
                                    self.photoDidChange = true
                                }
                            )
                            .padding(.top, 8)
                        }

                        // Notion-style title field
                        titleField
                            .padding(.top, 16)

                        // Spacious body editor
                        bodyField
                            .padding(.top, 16)

                        // Reserves the bottom chrome band so body text can never
                        // crowd the FABs. Matches resting overlay:
                        // edgeInset + 56 FAB + edgeInset.
                        Spacer(minLength: PositionedNewEntryFAB.edgeInset
                               + 56
                               + PositionedNewEntryFAB.edgeInset)
                    }
                    .padding(.horizontal, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    attachmentFAB
                    Spacer()
                    microphoneFAB
                }
                .padding(.horizontal, 24)
                .padding(.bottom, keyboardBottomPadding(geometry: geometry))
            }
        }
        .ignoresSafeArea(.keyboard)
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            restingHomeIndicator = Self.windowBottomSafeArea()
            setupInitialFocus()
        }
        .onChange(of: keyboardObserver.isKeyboardVisible) { _, visible in
            if !visible {
                restingHomeIndicator = Self.windowBottomSafeArea()
            }
        }
        .task {
            await preloadExistingPhotoIfNeeded()
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    handleNewPhoto(uiImage)
                }
                photoPickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCameraCapture) {
            CameraCapturePicker(
                onCapture: { image in
                    showCameraCapture = false
                    handleNewPhoto(image)
                },
                onCancel: { showCameraCapture = false }
            )
            .ignoresSafeArea()
        }
        .alert("Camera Unavailable", isPresented: $showCameraUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This device doesn't have a camera available.")
        }
        .alert("Camera Access Required", isPresented: $showCameraPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("MeetMemento needs camera access to add a photo. Enable it in Settings > Privacy > Camera.")
        }
        .onChange(of: speechService.isRecording) { oldValue, newValue in
            // When recording stops, insert if we already have final text
            // Only process if this view owns the session
            guard speechService.isOwner(speechOwnerId) else { return }
            if newValue == true {
                didConsumeTranscript = false
            } else if oldValue == true && !speechService.isProcessing {
                consumeTranscriptOnce(speechService.bestAvailableTranscript)
            }
        }
        .onChange(of: speechService.transcribedText) { _, newText in
            // Final transcription arrives asynchronously after stop; insert when it appears and we're not recording
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
                        .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(theme.foreground)
                        .frame(width: 44, height: 44)
                        .background(iconButtonBackground)
                }
                .accessibilityLabel("Back")
                .accessibilityHint("Double-tap to close without saving")

                Spacer()

                // Date pill
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .bold)) // icon-size: not user text
                    Text(formattedDate)
                        .font(type.body2Medium)
                }
                .foregroundStyle(theme.foreground)
                .padding(.horizontal, 14)
                // AX5: minHeight (not fixed height) lets the pill grow instead of
                // clipping/overlapping when the date text scales up at large Dynamic Type sizes.
                .frame(minHeight: 44)
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
                            .font(.system(size: 14, weight: .bold)) // icon-size: not user text
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(submitButtonBackground)
                    }
                }
                .disabled(isSaving || !hasSaveableContent)
                .accessibilityLabel(isSaving ? "Saving entry" : "Save entry")
                .accessibilityHint("Double-tap to save your journal entry")
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Button Backgrounds

    @ViewBuilder
    private var iconButtonBackground: some View {
        // Liquid Glass removed — flat themed surface — cardBackground adapts to dark mode.
        Circle()
            .fill(theme.cardBackground)
    }

    @ViewBuilder
    private var datePillBackground: some View {
        // Liquid Glass removed — flat themed surface — cardBackground adapts to dark mode.
        Capsule()
            .fill(theme.cardBackground)
    }

    @ViewBuilder
    private var submitButtonBackground: some View {
        // Dimmed state must track the same condition as `.disabled`, or a
        // photo-only entry would look unsavable while actually being savable.
        let baseColor = hasSaveableContent ? theme.primary : theme.primary.opacity(0.4)

        // Liquid Glass removed — brand color intentionally kept (prominent submit
        // action); flat purple fill, no glass or shadow.
        Circle()
            .fill(baseColor)
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
                    .font(.system(size: 22, weight: .bold)) // icon-size: not user text
                    .foregroundStyle(speechService.isRecording ? Color.red : theme.foreground)

                // Duration timer appears inside button when recording
                if speechService.isRecording {
                    Text(formatDuration(speechService.currentDuration))
                        .font(type.body1Bold)
                        .foregroundStyle(theme.destructive)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            // AX5: minHeight lets the pill grow instead of clipping the duration
            // timer text, which scales with Dynamic Type, when recording.
            .frame(minWidth: fabWidth, maxWidth: fabWidth, minHeight: 56)
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

    /// Leading attachment FAB (Figma node 393:4851): camera + photo-library
    /// icons, functional, plus a location pin shown for visual parity with
    /// Figma but non-interactive — location capture is a future feature.
    /// Reuses the same `theme.cardBackground` capsule chrome as `microphoneFAB`.
    /// Sizing: each icon gets a 44x44 frame — Apple's HIG minimum tap target —
    /// and the capsule's 6pt padding falls out of that. The arithmetic lands on
    /// Figma's FAB exactly: 6+44+4+44+4+44+6 = 152 wide, 6+44+6 = 56 tall.
    private static let optionButtonSize: CGFloat = 44
    private static let optionIconSize: CGFloat = 26

    private var attachmentFAB: some View {
        HStack(spacing: 4) {
            Button {
                presentCameraOrHandleUnavailable()
            } label: {
                Image(systemName: "camera")
                    .font(.system(size: Self.optionIconSize)) // icon-size: not user text
                    .foregroundStyle(theme.foreground)
                    .frame(width: Self.optionButtonSize, height: Self.optionButtonSize)
                    .contentShape(Rectangle()) // whole 44x44 is tappable, not just the glyph
            }
            .accessibilityLabel("Take photo")
            .accessibilityHint(photoData == nil ? "Double-tap to capture a photo with the camera" : "Double-tap to replace the current photo with a new one")

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: Self.optionIconSize)) // icon-size: not user text
                    .foregroundStyle(theme.foreground)
                    .frame(width: Self.optionButtonSize, height: Self.optionButtonSize)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Choose photo from library")
            .accessibilityHint(photoData == nil ? "Double-tap to choose a photo from your library" : "Double-tap to replace the current photo with one from your library")

            // Visible-but-disabled placeholder for Figma parity (boxicons:location).
            // A plain Image, not a disabled Button — that's what makes "disabled"
            // structurally true for VoiceOver instead of announcing an inert control.
            // Same 44x44 frame purely so the three icons keep an even rhythm.
            Image(systemName: "location")
                .font(.system(size: Self.optionIconSize)) // icon-size: not user text
                .foregroundStyle(theme.foreground.opacity(0.3))
                .frame(width: Self.optionButtonSize, height: Self.optionButtonSize)
                .accessibilityHidden(true)
        }
        .padding(6)
        .background(Capsule().fill(theme.cardBackground))
        .shadow(color: .black.opacity(0.08), radius: 16, x: 0, y: 8)
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

        // An attached photo is content in its own right — a photo with just a
        // title (or nothing else at all) is a valid entry, so don't gate purely
        // on body text or the photo becomes silently unsavable.
        guard hasSaveableContent else { return }

        isSaving = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        onSave(trimmedTitle, trimmedText, photoAction)

        isSaving = false
    }

    /// Whether there's anything worth saving: body text or an attached photo.
    private var hasSaveableContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoData != nil
    }

    /// Downscales/compresses the new photo and installs it as the current
    /// selection — used by both the camera and library paths. Replaces
    /// whatever photo was selected before (single photo per entry).
    ///
    /// The downscale + JPEG encode runs off the main thread: a 12MP camera
    /// photo through `UIGraphicsImageRenderer` is tens-to-hundreds of ms, which
    /// visibly stutters the capture-confirm transition if done inline.
    private func handleNewPhoto(_ image: UIImage) {
        Task {
            let prepared: (data: Data, image: UIImage)? = await Task.detached(priority: .userInitiated) {
                guard let data = ImageProcessor.prepareForStorage(image) else { return nil }
                return (data, UIImage(data: data) ?? image)
            }.value

            guard let prepared else { return }
            photoData = prepared.data
            photoPreviewImage = prepared.image
            photoDidChange = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// On `.edit(entry)` where the entry already has a photo, decrypts and
    /// preselects it so the composer previews what's already saved.
    /// `photoDidChange` stays false — this is a preload, not a user edit.
    ///
    /// Also guards on `!photoDidChange`, not just `photoPreviewImage == nil`:
    /// if the user has already removed the photo this session, a re-run of the
    /// enclosing `.task` must not silently resurrect it from disk.
    private func preloadExistingPhotoIfNeeded() async {
        guard let entry = editingEntry, entry.hasPhoto,
              photoPreviewImage == nil, !photoDidChange else { return }

        // Disk read + AES decrypt + JPEG decode off the main thread so opening
        // an entry with a photo doesn't hitch.
        let entryId = entry.id
        let loaded: (data: Data, image: UIImage)? = await Task.detached(priority: .userInitiated) {
            guard let encrypted = PhotoStorage.shared.loadEncrypted(entryId: entryId),
                  let data = JournalService.shared.encryptionService.decryptData(encrypted),
                  let uiImage = UIImage(data: data) else { return nil }
            return (data, uiImage)
        }.value

        // Re-check after the hop — the user may have acted while we loaded.
        guard let loaded, !photoDidChange else { return }
        photoData = loaded.data
        photoPreviewImage = loaded.image
    }

    /// Guards camera availability (always false on Simulator) and permission
    /// before presenting, mirroring the microphone's `showPermissionDenied` pattern.
    private func presentCameraOrHandleUnavailable() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailable = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCameraCapture = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showCameraCapture = true
                    } else {
                        showCameraPermissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            showCameraPermissionDenied = true
        @unknown default:
            showCameraPermissionDenied = true
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
    AddEntryView(state: .create) { _, _, _ in }
        .useTheme()
        .useTypography()
}

#Preview("Edit Entry") {
    AddEntryView(state: .edit(Entry.sampleEntries[0])) { _, _, _ in }
        .useTheme()
        .useTypography()
}

#Preview("Create Entry • Dark") {
    AddEntryView(state: .create) { _, _, _ in }
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Sheet Presentation") {
    Color.gray.opacity(0.3)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            AddEntryView(state: .create) { _, _, _ in }
                .presentationDetents([.fraction(0.95)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(32)
        }
        .useTheme()
        .useTypography()
}
