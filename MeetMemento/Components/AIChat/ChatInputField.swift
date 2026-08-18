//
//  ChatInputField.swift
//  MeetMemento
//
//  The chat composer: one 64pt capsule that morphs between three states.
//  Figma 433:1077 (State=Default) and 431:6079 (State=Narration).
//
//  - Default:   + · "Chat with Memento" · mic · voice button
//  - Chat:      + · growing text field · mic · send
//  - Narrate:   scrolling waveform · keyboard · send
//
//  Everything lives inside a single capsule now. The previous design was three
//  separate pills side by side plus a 280pt listening panel that took over the
//  bottom of the screen while dictating; the panel is gone and dictation renders
//  inline, which is why AIChatView no longer needs its narrate scrim.
//

import PhotosUI
import SwiftUI

struct ChatInputField: View {
    // MARK: - Input State Enum

    enum InputState: Equatable {
        case defaultState       // Placeholder + attach/mic/voice
        case chatActive         // Text field + attach/mic/send
        case narrateActive      // Waveform + keyboard/send
    }

    /// How a dictation session ends. Both endings are constructive — the words
    /// are always kept; the only question is whether they go out immediately or
    /// land in the field for editing. There is no discard: clearing the field
    /// is the escape hatch.
    enum DictationEnding {
        case handToField        // stop, insert into the composer, don't send
        case send               // stop, insert, and send straight away
    }

    // MARK: - Properties

    @Binding var text: String
    var onSend: () -> Void
    /// Called when the input field should be dismissed (e.g., tap outside)
    var onDismiss: (() -> Void)?
    /// Enters hands-free Narration Mode (the black waveform button). Only
    /// reachable from `.defaultState`, i.e. with an empty draft.
    var onNarrate: (() -> Void)?
    /// When false, input is disabled (e.g. while a send is in flight)
    var isInteractive: Bool
    /// For preview purposes - allows setting initial state
    var initialState: InputState

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inputState: InputState
    @FocusState private var isFocused: Bool
    @ObservedObject private var speechService = SpeechService.shared
    @State private var showPermissionDenied = false
    @State private var showSTTError = false
    /// Ensures one voice utterance is consumed exactly once (both speech observers can
    /// fire for the same utterance). Reset when a new recording starts.
    @State private var didConsumeTranscript = false
    /// What to do with the transcript once finalization delivers it. Both
    /// dictation buttons stop the recogniser and then wait on the same async
    /// hand-off, so the button that was tapped is the only thing that
    /// distinguishes them.
    @State private var dictationEnding: DictationEnding = .handToField

    // Photo attachment
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var attachedPhoto: UIImage?

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "ChatInputField"

    // MARK: - Design Constants

    /// Capsule height — same 64pt as Narration footer circles / FAB.
    private let pillHeight: CGFloat = AppHeaderMetrics.footerButtonSize
    /// Figma: every control in the bar is a 40pt circle.
    private let iconButtonSize: CGFloat = 40
    private let glyphSize: CGFloat = 22          // icon-size: not user text
    private let photoChipSize: CGFloat = 56

    /// Timing for the pill ⇄ composer morph.
    ///
    /// `.easeOut` rather than a spring, deliberately: this transition happens
    /// alongside the system keyboard, which animates on its own ease curve at a
    /// duration we don't control. `KeyboardObserver` republishes the height with
    /// that exact duration, so matching the shape here makes the composer, the
    /// conversation, and the keyboard travel together. A spring's overshoot read
    /// as a separate, later movement — invisible while the backdrop was blurred,
    /// obvious once it isn't. 0.25s matches the system keyboard's typical
    /// duration closely enough to read as one motion.
    ///
    /// The narrate transitions used to use `.spring(response: 0.4, ...)` instead,
    /// which is what made entering dictation read as a different, later motion
    /// from every other state change. They share this curve now.
    private static let stateChange: Animation = .easeOut(duration: 0.25)

    /// Whether the input is in an expanded state (chatActive or narrateActive)
    var isExpanded: Bool {
        inputState == .chatActive || inputState == .narrateActive
    }

    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initializer

    init(
        text: Binding<String>,
        onSend: @escaping () -> Void = {},
        onDismiss: (() -> Void)? = nil,
        onNarrate: (() -> Void)? = nil,
        isInteractive: Bool = true,
        initialState: InputState = .defaultState
    ) {
        self._text = text
        self.onSend = onSend
        self.onDismiss = onDismiss
        self.onNarrate = onNarrate
        self.isInteractive = isInteractive
        self.initialState = initialState
        self._inputState = State(initialValue: initialState)
    }

    // MARK: - Body

    var body: some View {
        // One stack so AIChatView's ComposerHeightKey measures the attachment
        // chip and transcript line too — anything that grows the composer has
        // to be inside this, or the message list reserves the wrong space.
        VStack(alignment: .leading, spacing: 8) {
            if let attachedPhoto {
                photoChip(attachedPhoto)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading)))
            }

            // NOTE: no live-transcript line while dictating. It used to sit
            // here, but as a real row it grew the composer ~48pt the instant the
            // mic was tapped — and `AIChatView` reserves the composer's measured
            // height, so the whole conversation jumped. Waveform-only while
            // recording is also what ChatGPT, WhatsApp voice notes, and system
            // dictation all do; the words appear in the field when you stop.
            // Nothing is posted without an explicit send gesture: the keyboard
            // button puts the words in the field to read and edit, and only the
            // send arrow sends.

            capsule
        }
        .accessibleAnimation(Self.stateChange, value: inputState)
        .accessibleAnimation(Self.stateChange, value: attachedPhoto != nil)
        .allowsHitTesting(isInteractive)
        // A single utterance can satisfy BOTH observers below (recording stops
        // with text present, then a final transcript lands). `consumeTranscriptOnce`
        // guards so exactly one hand-off fires per recording session. Where it
        // goes — the field, or straight out — is decided by which dictation
        // button was tapped; see `DictationEnding`.
        .onChange(of: speechService.isRecording) { oldValue, newValue in
            guard speechService.isOwner(speechOwnerId) else { return }
            if newValue == true {
                didConsumeTranscript = false            // new recording — arm one consume
            } else if oldValue == true {
                // Prefer waiting for finalization; if a final is already present, hand off now.
                if !speechService.isProcessing {
                    consumeTranscriptOnce(speechService.bestAvailableTranscript)
                }
            }
        }
        .onChange(of: speechService.transcribedText) { _, newText in
            guard speechService.isOwner(speechOwnerId) else { return }
            if !speechService.isRecording {              // final transcript after stop
                consumeTranscriptOnce(newText)
            }
        }
        .onChange(of: speechService.isProcessing) { _, processing in
            guard speechService.isOwner(speechOwnerId) else { return }
            // Finalization timeout / final callback cleared processing — hand off what we have.
            if !processing && !speechService.isRecording {
                consumeTranscriptOnce(speechService.bestAvailableTranscript)
            }
        }
        .onChange(of: isFocused) { _, newValue in
            // Return to default state when focus is lost in chatActive state.
            // The draft is intentionally kept: dismissing the keyboard by
            // tapping or scrolling the conversation must not erase what the
            // user has typed — reopening the input restores it.
            if !newValue && inputState == .chatActive {
                withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
                    inputState = .defaultState
                }
                onDismiss?()
            }
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
        .modifier(SpeechAlertsModifier(
            showPermissionDenied: $showPermissionDenied,
            showSTTError: $showSTTError,
            speechService: speechService,
            onRetry: { startListening() }
        ))
    }

    // MARK: - The Capsule

    private var capsule: some View {
        // `.top`, not the default `.center`. At rest every child is 40pt inside a
        // 64pt bar, so there is no slack and the two alignments are identical —
        // the resting spacing is untouched. Once the field wraps, though, centre
        // alignment drifts the controls down to the middle of a tall bar, away
        // from the line being typed. Top-aligning pins them beside the first
        // line, which is where the eye already is.
        HStack(alignment: .top, spacing: 8) {
            leadingContent

            // Trailing controls. Both are 40pt circles in every state; only the
            // glyph and the fill change, so the two slots stay put as the field
            // morphs instead of sliding around.
            HStack(alignment: .top, spacing: 8) {
                trailingSecondaryButton
                trailingPrimaryButton
            }
        }
        // Figma: px-12 by default, pl-24 while narrating (the waveform needs
        // the extra breathing room the + button used to occupy).
        .padding(.leading, inputState == .narrateActive ? 24 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, 12)
        // minHeight, not a fixed height: the field grows to five lines and
        // scales with Dynamic Type, and a hard 64 clips both.
        .frame(minHeight: pillHeight)
        .frame(maxWidth: .infinity)
        .rootEdgeInset()
        // Liquid Glass, `.regular` — the frosted variant, which is what spec 024
        // and the API reference both assign to this surface. `.clear` has
        // refraction but no frost, and this capsule floats over a scrolling
        // conversation, so the frosted legibility backing is the whole point.
        //
        // Applied to the padded HStack itself, NOT as a `.background(Capsule())`
        // layer. Only content composited *inside* the glass receives the
        // system's vibrancy treatment, which adapts colour and brightness to
        // whatever the glass is refracting; as a sibling background layer the
        // placeholder, glyphs and waveform would keep their literal token
        // colours and wash out. Same reasoning as `AvatarInitialButton`.
        //
        // No `.fill(...)` underneath: an opaque fill beneath glass renders it as
        // a flat panel and defeats it. That exact mistake on this very component
        // is the HIGH-severity row in spec 024's audit, and `.regular` already
        // supplies its own backing.
        //
        // No `GlassEffectContainer`: containers exist to blend *multiple*
        // neighbouring glass effects, and this is a single surface — the trailing
        // buttons are solid prominent controls composited on top, not glass.
        // Wrapping one effect is the "too many containers" antipattern.
        //
        // Not `.interactive()` either: the bar is a surface that holds buttons
        // rather than something pressed directly, and interactive glass here
        // would light the whole bar up when the mic or send is tapped.
        //
        // A fixed 32pt radius rather than `.capsule`. A capsule's radius is half
        // its height, so at the resting 64pt the two are identical — but the
        // field grows to five lines, and the capsule's corners would swell with
        // it. Pinning the token keeps the silhouette constant while typing.
        .glassEffect(.regular, in: .rect(cornerRadius: theme.radius.xxl, style: .continuous))
    }

    // MARK: - Leading Content

    @ViewBuilder
    private var leadingContent: some View {
        switch inputState {
        case .defaultState:
            HStack(spacing: 4) {
                attachButton
                // Only this region opens the composer. The + and the two
                // trailing buttons are siblings inside the capsule, so wrapping
                // the whole bar in a Button would swallow their taps.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
                        inputState = .chatActive
                    }
                    // Request focus HERE rather than in an onAppear. Focusing
                    // on appear meant the sequence was: animation starts → view
                    // appears → focus → keyboard notification → content shifts.
                    // The composer and the conversation therefore moved on two
                    // different curves, one beat apart. Asking for focus in the
                    // same turn as the state change lets the keyboard begin
                    // rising with the morph.
                    isFocused = true
                } label: {
                    HStack(spacing: 0) {
                        Text("Chat with Memento")
                            .font(type.inputLarge)
                            .foregroundStyle(theme.mutedForeground)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: iconButtonSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chat with Memento")
                .accessibilityHint("Double-tap to write a message")
            }

        case .chatActive:
            // Also `.top`: the attach button has to stay level with the first
            // line for the same reason as the trailing pair, otherwise it alone
            // slides to the middle as the text wraps.
            HStack(alignment: .top, spacing: 4) {
                attachButton
                TextField(
                    "",
                    text: $text,
                    prompt: Text("Chat with Memento").foregroundStyle(theme.mutedForeground),
                    axis: .vertical
                )
                .font(type.inputLarge)
                .foregroundStyle(theme.foreground)
                .focused($isFocused)
                .lineLimit(1...5)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.return)
                // Vertically centers a single line against the round buttons.
                .frame(minHeight: iconButtonSize)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .narrateActive:
            DictationWaveform(audioLevel: speechService.audioLevel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: iconButtonSize)
        }
    }

    // MARK: - Attach Button (Figma "ic:round-plus")

    private var attachButton: some View {
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            Image(systemName: "plus")
                .font(.system(size: glyphSize, weight: .medium)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .frame(width: iconButtonSize, height: iconButtonSize)
                .contentShape(Circle())
        }
        .accessibilityLabel("Attach photo")
        .accessibilityHint(
            attachedPhoto == nil
            ? "Double-tap to choose a photo from your library"
            : "Double-tap to replace the attached photo"
        )
    }

    // MARK: - Trailing Buttons

    /// Left of the pair. Starts dictation; hands the words to the field while
    /// dictating.
    @ViewBuilder
    private var trailingSecondaryButton: some View {
        let recording = inputState == .narrateActive

        Button {
            if recording {
                finishListening(.handToField)
            } else {
                startListening()
            }
        } label: {
            // `keyboard` rather than Figma's plain mic, because while recording
            // this button means "stop listening and let me type" — it commits
            // what was heard to the field instead of sending it. A mic here
            // would compete with the send arrow beside it, and the earlier
            // mic.slash was worse still: it now reads as discard, which this no
            // longer does.
            Image(systemName: recording ? "keyboard" : "mic")
                .font(.system(size: glyphSize, weight: .medium)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: iconButtonSize, height: iconButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording ? "Insert dictated text" : "Dictate")
        .accessibilityHint(
            recording
            ? "Double-tap to stop recording and put the words in the message field to edit"
            : "Double-tap to speak your message"
        )
    }

    /// Right of the pair. Sends while composing *and* while dictating — the
    /// slot means "send" in both, so the arrow never changes meaning under the
    /// user's thumb. Only the resting state differs, where it holds the place
    /// of the hands-free voice mode.
    @ViewBuilder
    private var trailingPrimaryButton: some View {
        switch inputState {
        case .defaultState:
            voiceModeButton
        case .chatActive:
            sendButton
        case .narrateActive:
            dictationSendButton
        }
    }

    /// Figma "solar:soundwave-bold" on a #1C2329 circle. Enters hands-free
    /// narration on the chat page (`AIChatView.startNarration`).
    private var voiceModeButton: some View {
        Button {
            onNarrate?()
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: glyphSize, weight: .semibold)) // icon-size: not user text
                // theme.foreground is gray900 (#1C2329, Figma's exact fill) in
                // light and gray50 in dark, so the button inverts correctly
                // instead of staying a near-black disc on a dark background.
                .foregroundStyle(theme.background)
                .frame(width: iconButtonSize, height: iconButtonSize)
                .background(Circle().fill(theme.foreground))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hands-free voice")
        .accessibilityHint("Double-tap to start a voice conversation")
    }

    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: glyphSize, weight: .bold)) // icon-size: not user text
                .foregroundStyle(.white)
                .frame(width: iconButtonSize, height: iconButtonSize)
                .background(
                    Circle().fill(isTextEmpty ? theme.primary.opacity(0.5) : theme.primary)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isTextEmpty)
        .accessibilityLabel("Send message")
    }

    /// Stop dictating and send in one gesture. Deliberately the same prominent
    /// treatment as `sendButton` rather than Figma's red stop (`431:6079`): the
    /// action is a send, so it should look like the send it is.
    private var dictationSendButton: some View {
        Button {
            finishListening(.send)
        } label: {
            Group {
                if speechService.isProcessing {
                    // `stopRecording()` removes the audio tap, so the waveform
                    // goes flat for up to 1.8s while the final transcript
                    // resolves. Without a cue here there'd be nothing at all —
                    // this fills the same 40pt circle, so nothing moves.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: glyphSize, weight: .bold)) // icon-size: not user text
                        .foregroundStyle(.white)
                }
            }
            .frame(width: iconButtonSize, height: iconButtonSize)
            .background(Circle().fill(theme.primary))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // Not gated on whether anything has been heard yet: the partial
        // transcript lags the speech, so a dimmed send mid-sentence reads as
        // broken. An empty dictation is handled at the other end — the
        // finalization path returns to rest and posts nothing.
        //
        // Also deliberately NOT disabled while processing. Finalization can
        // hang (it does on the simulator, leaving the spinner up), and a
        // disabled primary control in that state strands the user.
        .accessibilityLabel(speechService.isProcessing ? "Sending dictation" : "Send dictation")
        .accessibilityHint("Double-tap to stop recording and send what was heard")
    }

    // MARK: - Photo Chip

    private func photoChip(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: photoChipSize, height: photoChipSize)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    attachedPhoto = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20)) // icon-size: not user text
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(theme.background, theme.foreground)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove photo")
            }
            .padding(.leading, 12)
            .padding(.top, 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Attached photo")
    }

    // MARK: - Live Transcript

    /// Shown above the capsule while dictating so a mishearing is visible
    /// before the user commits it (REQ-CAP-003 honesty signal). This used to
    /// sit inside the 280pt listening panel; the panel is gone, the signal isn't.
    @ViewBuilder
    private var liveTranscriptLabel: some View {
        let live = speechService.partialTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = speechService.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = final.isEmpty ? live : final
        let placeholder = speechService.isRecording ? "Listening…" : "Finishing…"

        Text(display.isEmpty ? placeholder : display)
            .font(type.body2)
            .foregroundStyle(final.isEmpty ? theme.mutedForeground : theme.foreground)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .accessibilityLabel(display.isEmpty ? placeholder : "Transcription: \(display)")
    }

    // MARK: - Photo Actions

    /// Downscales/compresses off the main thread — a 12MP library photo through
    /// `UIGraphicsImageRenderer` is tens-to-hundreds of ms, which would stutter
    /// the picker dismissal if done inline. Mirrors `AddEntryView.handleNewPhoto`.
    private func handleNewPhoto(_ image: UIImage) {
        Task {
            let prepared: UIImage? = await Task.detached(priority: .userInitiated) {
                guard let data = ImageProcessor.prepareForStorage(image) else { return nil }
                return UIImage(data: data)
            }.value

            await MainActor.run {
                guard let prepared else { return }
                withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
                    attachedPhoto = prepared
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    // MARK: - Speech Actions

    private func startListening() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        didConsumeTranscript = false
        // Reset the ending every session. A stale `.send` left over from the
        // previous dictation is the one way this could silently post a
        // transcript the user never asked to send.
        dictationEnding = .handToField

        withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
            inputState = .narrateActive
        }

        Task {
            do {
                try await speechService.startRecording(ownerId: speechOwnerId)
            } catch let error as SpeechService.SpeechError {
                collapseNarrateToDefault()
                if case .permissionDenied = error {
                    showPermissionDenied = true
                } else {
                    showSTTError = true
                }
            } catch {
                collapseNarrateToDefault()
                showSTTError = true
            }
        }
    }

    /// End dictation. `ending` decides what happens when the transcript lands —
    /// it is read later, on the async finalization path, which is why it is
    /// recorded here rather than passed through.
    private func finishListening(_ ending: DictationEnding) {
        dictationEnding = ending
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        Task {
            await speechService.stopRecording()
            // Observers hand off when finalization completes. Safety net if nothing arrives.
            try? await Task.sleep(nanoseconds: 1_800_000_000)

            await MainActor.run {
                guard !didConsumeTranscript else { return }
                let fallback = speechService.bestAvailableTranscript
                if fallback.isEmpty {
                    // Nothing was heard. Return to rest — notably this does NOT
                    // send, even on the `.send` path, so an empty tap can't post
                    // a blank prompt.
                    collapseNarrateToDefault()
                    speechService.clearTranscription()
                } else {
                    consumeTranscriptOnce(fallback)
                }
            }
        }
    }

    private func collapseNarrateToDefault() {
        withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
            inputState = .defaultState
        }
    }

    private func sendMessage() {
        guard !isTextEmpty else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSend()
        // Return to default state after sending
        text = ""
        // TODO: chat runs on the text-only on-device SystemLanguageModel, so
        // nothing consumes the attachment yet — it is cleared with the draft
        // rather than silently carried into the next message.
        attachedPhoto = nil
        inputState = .defaultState
        isFocused = false
    }

    /// Consume the transcript at most once per recording session, so multiple
    /// speech observers can't all hand it off.
    ///
    /// This never *auto*-sends. The `.send` ending only exists because the user
    /// tapped the send arrow to finish the dictation, so the invariant is
    /// "nothing goes out without an explicit send gesture" — a misheard phrase
    /// still can't post itself on the hand-to-field path.
    private func consumeTranscriptOnce(_ transcribedText: String) {
        guard !didConsumeTranscript else { return }
        let trimmed = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        didConsumeTranscript = true
        deliverTranscript(trimmed)
    }

    private func deliverTranscript(_ transcribedText: String) {
        if text.isEmpty {
            text = transcribedText
        } else {
            text += (text.hasSuffix("\n") ? "" : "\n") + transcribedText
        }

        // Clear transcription buffer and release ownership
        speechService.clearTranscription()

        switch dictationEnding {
        case .send:
            // `sendMessage()` guards empty text, clears the draft and the
            // attachment, and returns the field to rest.
            sendMessage()

        case .handToField:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Hand control back to the user: edit or send from the composer.
            withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
                inputState = .chatActive
            }
            isFocused = true
        }
    }
}

// MARK: - Speech Alerts Modifier

private struct SpeechAlertsModifier: ViewModifier {
    @Binding var showPermissionDenied: Bool
    @Binding var showSTTError: Bool
    let speechService: SpeechService
    var onRetry: () -> Void

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
                Text(
                    "MeetMemento needs microphone access to transcribe your voice. "
                    + "Enable it in Settings > Privacy > Microphone."
                )
            }
            .alert("Recording Failed", isPresented: $showSTTError) {
                Button("Try Again") {
                    onRetry()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(speechService.errorMessage ?? "Unable to start recording. Please try again.")
            }
    }
}

// MARK: - Previews

#Preview("Default State") {
    ChatInputFieldPreview(initialState: .defaultState)
        .useTheme()
        .useTypography()
}

#Preview("Chat Active") {
    ChatInputFieldPreview(initialState: .chatActive, text: "What patterns do you see?")
        .useTheme()
        .useTypography()
}

#Preview("Narrate Active") {
    ChatInputFieldPreview(initialState: .narrateActive)
        .useTheme()
        .useTypography()
}

#Preview("Dark Mode - Default") {
    ChatInputFieldPreview(initialState: .defaultState)
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Dark Mode - Narrate") {
    ChatInputFieldPreview(initialState: .narrateActive)
        .useTheme()
        .useTypography()
        .preferredColorScheme(.dark)
}

#Preview("Large Dynamic Type") {
    ChatInputFieldPreview(initialState: .defaultState)
        .useTheme()
        .useTypography()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Interactive") {
    ChatInputFieldPreview(initialState: .defaultState)
        .useTheme()
        .useTypography()
}

private struct ChatInputFieldPreview: View {
    let initialState: ChatInputField.InputState
    @State private var text: String

    init(initialState: ChatInputField.InputState, text: String = "") {
        self.initialState = initialState
        self._text = State(initialValue: text)
    }

    var body: some View {
        VStack {
            Spacer()
            ChatInputField(
                text: $text,
                onSend: { AppLogger.log("Send: \(text)") },
                initialState: initialState
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }
}
