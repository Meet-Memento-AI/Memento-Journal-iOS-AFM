//
//  ChatInputField.swift
//  MeetMemento
//
//  The chat composer: one glass capsule that morphs between three states.
//  Figma 433:1077 (State=Default), 431:6079 (State=Narration),
//  431:5946 (attachments inside the glass).
//
//  - Default:   + · "Chat with Memento" · mic · voice button
//  - Chat:      + · growing text field · mic · send
//  - Narrate:   scrolling waveform · keyboard · send
//
//  Attached photos sit in a 112pt row *inside* the same glass, above the
//  input row — not as a chip outside it. Up to three, equal flex, 16pt
//  corners, close control on each thumb.
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
    /// JPEG bytes for photos attached to this draft. Empty when the send is
    /// text-only. Fired *before* the field clears the draft, same as the
    /// pre-send geometry capture.
    var onSend: ([Data]) -> Void
    /// Called when the input field should be dismissed (e.g., tap outside)
    var onDismiss: (() -> Void)?
    /// Enters hands-free Narration Mode (the black waveform button). Only
    /// reachable from `.defaultState`, i.e. with an empty draft.
    var onNarrate: (() -> Void)?
    /// When false, input is disabled (e.g. while a send is in flight)
    var isInteractive: Bool
    /// Reports the capsule's frame in `ChatSpace.page` after every layout.
    ///
    /// The send choreography reads the last reported value at send time, which
    /// is necessarily the *pre-send* geometry: `sendMessage()` fires `onSend()`
    /// before it clears the text and collapses the field, and geometry
    /// callbacks are post-layout.
    var onComposerFrame: ((CGRect) -> Void)?
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

    // Photo attachments (Figma 431:5946 — up to three, inside the glass).
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var attachedPhotos: [AttachedChatPhoto] = []

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "ChatInputField"

    // MARK: - Design Constants

    /// Capsule height — same 64pt as Narration footer circles / FAB.
    private let pillHeight: CGFloat = AppHeaderMetrics.footerButtonSize
    /// Figma: every control in the bar is a 40pt circle.
    private let iconButtonSize: CGFloat = 40
    private let glyphSize: CGFloat = 22          // icon-size: not user text
    /// Figma 431:5946 — attachment thumbs inside the glass.
    private let photoThumbHeight: CGFloat = 112
    private static let maxAttachments = 3
    private static let photoThumbSpacing: CGFloat = 8
    /// Figma close control, inset from the thumb's top-trailing corner.
    private let photoCloseInset: CGFloat = 10
    private let photoCloseSize: CGFloat = 24

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

    private var canSend: Bool {
        !isTextEmpty || !attachedPhotos.isEmpty
    }

    private var remainingAttachmentSlots: Int {
        max(0, Self.maxAttachments - attachedPhotos.count)
    }

    // MARK: - Initializer

    init(
        text: Binding<String>,
        onSend: @escaping ([Data]) -> Void = { _ in },
        onDismiss: (() -> Void)? = nil,
        onNarrate: (() -> Void)? = nil,
        isInteractive: Bool = true,
        initialState: InputState = .defaultState,
        onComposerFrame: ((CGRect) -> Void)? = nil
    ) {
        self._text = text
        self.onSend = onSend
        self.onDismiss = onDismiss
        self.onNarrate = onNarrate
        self.isInteractive = isInteractive
        self.initialState = initialState
        self.onComposerFrame = onComposerFrame
        self._inputState = State(initialValue: initialState)
    }

    // MARK: - Body

    var body: some View {
        // One stack so AIChatView's ComposerHeightKey measures the attachment
        // row too — anything that grows the composer has to be inside this, or
        // the message list reserves the wrong space. Attachments live *inside*
        // `capsule` (Figma 431:5946), not as a sibling chip above the glass.
        capsule
        .accessibleAnimation(Self.stateChange, value: inputState)
        .accessibleAnimation(Self.stateChange, value: attachedPhotos.map(\.id))
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
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await ingestPickerItems(items) }
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
        // Attachments (when present) sit above the input row *inside* the same
        // glass, matching Figma 431:5946: 112pt thumbs, 8pt gap, 10pt column
        // gap, then the 64pt input row. Without photos this collapses to the
        // original padded HStack so the resting 64pt silhouette is unchanged.
        VStack(alignment: .leading, spacing: 10) {
            if !attachedPhotos.isEmpty {
                attachmentRow
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
            }

            inputRow
                .padding(.leading, inputState == .narrateActive ? 12 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.top, attachedPhotos.isEmpty ? 0 : 12)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity)
        .rootEdgeInset()
        // Liquid Glass, `.regular` — the frosted variant, which is what spec 024
        // and the API reference both assign to this surface. `.clear` has
        // refraction but no frost, and this capsule floats over a scrolling
        // conversation, so the frosted legibility backing is the whole point.
        //
        // Applied to the padded stack itself, NOT as a `.background(Capsule())`
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ChatSpace.page)) }
            action: { onComposerFrame?($0) }
    }

    /// The + / field / trailing-controls row. Figma's input row is always the
    /// 64pt bar (`py-12` around 40pt circles), whether or not thumbs sit above.
    private var inputRow: some View {
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
        .padding(.vertical, 12)
        .frame(minHeight: pillHeight)
        .frame(maxWidth: .infinity)
    }

    /// Figma 431:5946: three equal-flex 112pt thumbs, 8pt gap, 16pt corners.
    private var attachmentRow: some View {
        HStack(spacing: Self.photoThumbSpacing) {
            ForEach(attachedPhotos) { photo in
                photoThumb(photo)
                    .frame(maxWidth: .infinity)
                    .frame(height: photoThumbHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            attachedPhotos.count == 1
            ? "1 photo attached"
            : "\(attachedPhotos.count) photos attached"
        )
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
        PhotosPicker(
            selection: $photoPickerItems,
            maxSelectionCount: max(1, remainingAttachmentSlots),
            matching: .images
        ) {
            Image(systemName: "plus")
                .font(.system(size: glyphSize, weight: .medium)) // icon-size: not user text
                .foregroundStyle(theme.foreground)
                .frame(width: iconButtonSize, height: iconButtonSize)
                .contentShape(Circle())
        }
        .disabled(remainingAttachmentSlots == 0)
        .opacity(remainingAttachmentSlots == 0 ? 0.4 : 1)
        .accessibilityLabel("Attach photo")
        .accessibilityHint(attachAccessibilityHint)
        .accessibilityValue(
            attachedPhotos.isEmpty
            ? "No photos attached"
            : "\(attachedPhotos.count) of \(Self.maxAttachments) photos attached"
        )
    }

    private var attachAccessibilityHint: String {
        if remainingAttachmentSlots == 0 {
            return "You can attach up to \(Self.maxAttachments) photos"
        }
        if attachedPhotos.isEmpty {
            return "Double-tap to choose photos from your library"
        }
        return "Double-tap to add another photo"
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
                    Circle().fill(canSend ? theme.primary : theme.primary.opacity(0.5))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
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

    // MARK: - Photo Thumbs (Figma 431:5946)

    private func photoThumb(_ photo: AttachedChatPhoto) -> some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, minHeight: photoThumbHeight, maxHeight: photoThumbHeight)
            .clipped()
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    removePhoto(photo.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: photoCloseSize)) // icon-size: not user text
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(theme.background, theme.foreground)
                        .frame(width: photoCloseSize, height: photoCloseSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(photoCloseInset)
                .accessibilityLabel("Remove photo")
            }
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

    /// Loads picker items in order, downscales off the main thread, and appends
    /// up to `maxAttachments`. Mirrors `AddEntryView.handleNewPhoto`.
    @MainActor
    private func ingestPickerItems(_ items: [PhotosPickerItem]) async {
        photoPickerItems = []
        var remaining = remainingAttachmentSlots
        guard remaining > 0 else { return }

        for item in items.prefix(remaining) {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data) else { continue }
            await appendPreparedPhoto(uiImage)
            remaining -= 1
            if remaining == 0 { break }
        }
    }

    /// Downscales/compresses off the main thread — a 12MP library photo through
    /// `UIGraphicsImageRenderer` is tens-to-hundreds of ms, which would stutter
    /// the picker dismissal if done inline.
    private func appendPreparedPhoto(_ image: UIImage) async {
        let prepared: (UIImage, Data)? = await Task.detached(priority: .userInitiated) {
            guard let data = ImageProcessor.prepareForStorage(image),
                  let uiImage = UIImage(data: data) else { return nil }
            return (uiImage, data)
        }.value

        guard let prepared else { return }
        guard attachedPhotos.count < Self.maxAttachments else { return }
        withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
            attachedPhotos.append(AttachedChatPhoto(image: prepared.0, jpeg: prepared.1))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func removePhoto(_ id: UUID) {
        withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
            attachedPhotos.removeAll { $0.id == id }
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
                    // Nothing was heard. Photos-only still sends — the draft
                    // has something to post. An empty tap with no photos does
                    // not, even on the `.send` path.
                    if dictationEnding == .send && !attachedPhotos.isEmpty {
                        sendMessage()
                    } else {
                        collapseNarrateToDefault()
                        speechService.clearTranscription()
                    }
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
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSend(attachedPhotos.map(\.jpeg))
        // Return to default state after sending
        text = ""
        attachedPhotos = []
        inputState = .defaultState
        // Focus is deliberately NOT dropped here. Dismissing the keyboard on
        // send dragged the footer ~300pt during the send flight and forced the
        // flight onto an ease curve to avoid fighting the system's keyboard
        // timing. Keeping it up matches ChatGPT/Grok, makes consecutive sends
        // possible without the bar flapping, and frees the flight to use a
        // spring. `onDismissKeyboard` and interactive scroll dismissal are
        // still the ways out.
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
            // `sendMessage()` guards empty drafts, clears the text and the
            // attachments, and returns the field to rest.
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

// MARK: - Attached photo (composer draft)

/// One photo in the composer's in-glass attachment row. `jpeg` is the
/// downscaled payload handed to `onSend`; `image` is the preview.
private struct AttachedChatPhoto: Identifiable, Equatable {
    let id: UUID
    let image: UIImage
    let jpeg: Data

    init(id: UUID = UUID(), image: UIImage, jpeg: Data) {
        self.id = id
        self.image = image
        self.jpeg = jpeg
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
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
                onSend: { _ in AppLogger.log("Send: \(text)") },
                initialState: initialState
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }
}
