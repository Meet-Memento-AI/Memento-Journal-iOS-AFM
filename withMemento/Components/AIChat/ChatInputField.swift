//
//  ChatInputField.swift
//  withMemento
//
//  The chat composer: one glass capsule that morphs between three states.
//  Figma 433:1077 (Default), 976:2838 (single-line typing), 976:2850
//  (paragraph — 24pt corners), 431:6079 (Narration).
//
//  - Default:   "Chat with Memento" · mic · voice button
//  - Chat:      growing text field · mic · send
//  - Narrate:   scrolling waveform · keyboard · send
//
//  Text and voice only. The composer used to attach up to three photos
//  through a `+` PhotosPicker; that was removed, so nothing here touches the
//  photo library.
//
//  Everything lives inside a single capsule now. The previous design was three
//  separate pills side by side plus a 280pt listening panel that took over the
//  bottom of the screen while dictating; the panel is gone and dictation renders
//  inline, which is why AIChatView no longer needs its narrate scrim.
//

import SwiftUI

struct ChatInputField: View {
    // MARK: - Input State Enum

    enum InputState: Equatable {
        case defaultState       // Placeholder + mic/voice
        case chatActive         // Text field + mic/send
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
    /// Fired *before* the field clears the draft, same as the pre-send
    /// geometry capture.
    var onSend: () -> Void
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

    /// Text block height in `.chatActive`. When it exceeds one 48pt line,
    /// Figma 976:2850 top-aligns the row and pins corners at 24.
    @State private var textBlockHeight: CGFloat = 0

    /// Unique identifier for this view's speech session ownership
    private let speechOwnerId = "ChatInputField"

    // MARK: - Design Constants

    /// Capsule height — 8pt inset around 48pt trailing controls (Figma p-[8px]).
    private let pillHeight: CGFloat = AppHeaderMetrics.composerMinHeight
    /// Mic layout slot. 48pt so the row stays aligned with header chrome.
    private let iconButtonSize: CGFloat = AppHeaderMetrics.controlSize
    /// Filled narrate / send discs. Figma is 40pt (`theme.radius.lg` × 2);
    /// the 48pt slot around them is the tap target, not the painted circle.
    private var prominentButtonSize: CGFloat { theme.radius.lg * 2 }
    private var glyphFont: Font { AppHeaderMetrics.controlSymbolFont }
    /// Canvas tint through `.regular` glass — densifies frost so typed text
    /// stays readable over the thread. Lighter than Welcome's 0.24 CTA tint
    /// so the bar stays a surface, not a filled button.
    private static let glassFrostTintOpacity: Double = 0.2

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

    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSend: Bool {
        !isTextEmpty
    }

    /// Figma 976:2850 — wrapped typing, not the single-line pill.
    /// Newlines always count; soft-wrap waits until the field is clearly
    /// taller than one 48pt line so the corner radius doesn't oscillate.
    private var isParagraphLayout: Bool {
        guard inputState == .chatActive else { return false }
        if text.contains(where: { $0.isNewline }) { return true }
        return textBlockHeight > iconButtonSize + 8
    }

    // MARK: - Initializer

    init(
        text: Binding<String>,
        onSend: @escaping () -> Void = {},
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
        self.onComposerFrame = onComposerFrame
        self._inputState = State(initialValue: initialState)
    }

    // MARK: - Body

    var body: some View {
        // Anything that grows the composer has to be inside `capsule`, or
        // AIChatView's ComposerHeightKey reserves the wrong space.
        capsule
        .accessibleAnimation(Self.stateChange, value: inputState)
        .accessibleAnimation(Self.stateChange, value: isParagraphLayout)
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
                textBlockHeight = 0
                onDismiss?()
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
        inputRow
            .padding(.leading, inputState == .narrateActive ? Spacing.sm : 0)
            .padding(.horizontal, Spacing.xs)
        .frame(maxWidth: .infinity)
        .pageColumnRelative()
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
        // is the HIGH-severity row in spec 024's audit. A light canvas tint
        // through the material (same pattern as Welcome's Get Started) densifies
        // the frost so placeholder and typed text stay readable over the thread.
        // Reduce Transparency is the one exception: `mementoChromeGlass` swaps
        // the glass for an opaque `theme.card` plate.
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
        // Rest / single-line stays 32pt (a pill at the 64pt well). Wrapped
        // typing (Figma 976:2850) pins 24pt so the corners don't swell with
        // five lines.
        .mementoChromeGlass(
            .regular.tint(theme.background.opacity(Self.glassFrostTintOpacity)),
            in: .rect(
                cornerRadius: isParagraphLayout ? theme.radius.xl : theme.radius.xxl,
                style: .continuous
            )
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ChatSpace.page)) }
            action: { onComposerFrame?($0) }
    }

    /// Figma's input row is 8pt inset around the controls. Single-line stays
    /// a pill (text · trailing). Wrapped typing (976:2850) pins the trailing
    /// pair to the first line.
    private var inputRow: some View {
        HStack(alignment: isParagraphLayout ? .top : .center, spacing: Spacing.xs) {
            leadingColumn
            trailingControls
        }
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: pillHeight)
        .frame(maxWidth: .infinity)
    }

    private var trailingControls: some View {
        HStack(spacing: Spacing.xs) {
            trailingSecondaryButton
            trailingPrimaryButton
        }
    }

    // MARK: - Leading Content

    /// Figma placeholder `#8D97A3`. `mutedForeground` is gray600 in light
    /// (too dark for this caption); gray400 is the nearest token in both modes.
    private var composerPlaceholder: Color { GrayScale.gray400 }

    @ViewBuilder
    private var leadingColumn: some View {
        switch inputState {
        case .defaultState:
            placeholderOpenButton

        case .chatActive:
            composerTextField

        case .narrateActive:
            DictationWaveform(audioLevel: speechService.audioLevel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: iconButtonSize)
        }
    }

    /// Only this region opens the composer. The two trailing buttons are
    /// siblings inside the capsule, so wrapping the whole bar in a Button
    /// would swallow their taps.
    private var placeholderOpenButton: some View {
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
                // At accessibility sizes the full prompt truncated to
                // "Chat w…"; a whole shorter word reads better than a cut one.
                ViewThatFits(in: .horizontal) {
                    Text("Chat with Memento")
                    Text("Chat")
                }
                .font(type.inputLarge)
                .foregroundStyle(composerPlaceholder)
                .lineLimit(1)
                Spacer(minLength: Spacing.xs)
            }
            .padding(.horizontal, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chat with Memento")
        .accessibilityHint("Double-tap to write a message")
    }

    private var composerTextField: some View {
        TextField(
            "",
            text: $text,
            prompt: Text("Chat with Memento").foregroundStyle(composerPlaceholder),
            axis: .vertical
        )
        .font(type.inputLarge)
        .foregroundStyle(theme.foreground)
        .focused($isFocused)
        .lineLimit(1...5)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.return)
        .padding(.horizontal, Spacing.xs)
        .frame(minHeight: iconButtonSize)
        .frame(maxWidth: .infinity, alignment: .leading)
        .id("chatComposerField")
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textBlockHeight = $0 }
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
                .font(glyphFont)
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onNarrate?()
        } label: {
            Image(systemName: "waveform")
                .font(glyphFont)
                .foregroundStyle(theme.primaryForeground)
                .modifier(ProminentComposerCircle(
                    size: prominentButtonSize,
                    slot: iconButtonSize,
                    fill: theme.primaryButtonFill
                ))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hands-free voice")
        .accessibilityHint("Double-tap to start a voice conversation")
    }

    /// Figma 976:2838 / 976:2850 — same dark disc as the resting waveform
    /// control (`#171717`), not the brand fill. Glyph inverts with the theme.
    private var sendButton: some View {
        Button(action: sendMessage) {
            Image(systemName: "arrow.up")
                .font(glyphFont.weight(.bold))
                .foregroundStyle(theme.primaryForeground)
                .modifier(ProminentComposerCircle(
                    size: prominentButtonSize,
                    slot: iconButtonSize,
                    fill: theme.primaryButtonFill,
                    fillOpacity: canSend ? 1 : 0.5
                ))
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
                    // this fills the same 40pt disc, so nothing moves.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.primaryForeground)
                } else {
                    Image(systemName: "arrow.up")
                        .font(glyphFont.weight(.bold))
                        .foregroundStyle(theme.primaryForeground)
                }
            }
            .modifier(ProminentComposerCircle(
                size: prominentButtonSize,
                slot: iconButtonSize,
                fill: theme.primaryButtonFill
            ))
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

    // MARK: - Live Transcript

    /// Shown above the capsule while dictating so a mishearing is visible
    /// before the user commits it (REQ-CAP-003 honesty signal). This used to
    /// sit inside the 280pt listening panel; the panel is gone, the signal isn't.
    // periphery:ignore - not mounted since the listening panel went; re-mounting is a product call
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
                    // Nothing was heard. An empty tap posts nothing, even on
                    // the `.send` path.
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
        guard canSend else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onSend()
        // Return to default state after sending
        text = ""
        textBlockHeight = 0
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
            // `sendMessage()` guards empty drafts, clears the text, and
            // returns the field to rest.
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

/// 40pt filled disc centered in the 48pt composer slot.
private struct ProminentComposerCircle: ViewModifier {
    let size: CGFloat
    let slot: CGFloat
    let fill: LinearGradient
    var fillOpacity: Double = 1

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(Circle().fill(fill).opacity(fillOpacity))
            .frame(width: slot, height: slot)
            .contentShape(Circle())
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
                    "withMemento needs microphone access to transcribe your voice. "
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

#Preview("Paragraph Typing") {
    ChatInputFieldPreview(
        initialState: .chatActive,
        text: "I've been noticing the same loop at work — I freeze, then I replay the conversation, then I write it down. What do you see in that?"
    )
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

// periphery:ignore - constructed only by #Preview
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
