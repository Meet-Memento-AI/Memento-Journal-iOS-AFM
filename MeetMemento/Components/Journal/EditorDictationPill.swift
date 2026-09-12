//
//  EditorDictationPill.swift
//  MeetMemento
//
//  Voice-dictation control for the journal editor (PRES-024): mic at rest,
//  red stop plus live duration while listening.
//
//  It owns the speech session rather than `AddEntryView` observing
//  `SpeechService` directly. The service publishes roughly fifty times a
//  second while recording (audio level and VAD at 20 Hz, duration at 10 Hz),
//  and at the editor root every one of those re-evaluated the full-bleed
//  backdrop, the four glass surfaces and the body editor. Scoped here, they
//  invalidate a 56pt pill.
//

import SwiftUI
import UIKit

struct EditorDictationPill: View {
    /// Session-ownership key. `SpeechService` is a singleton shared with the
    /// chat composer, so every observer below filters on it.
    let ownerId: String
    /// Editor chrome tint: `theme.foreground` (black in light, white in dark).
    let foreground: Color
    /// `.interactive()` press refraction. The editor passes `!reduceMotion`;
    /// nil reads the environment so previews and other hosts stay correct.
    var interactive: Bool? = nil
    /// Trimmed transcript, handed back for insertion into the body.
    let onTranscript: (String) -> Void

    @ObservedObject private var speechService = SpeechService.shared

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var phase: Phase = .idle
    /// Guards against double-insert: three observers race to hand off one
    /// session's transcript and only the first may win.
    @State private var didConsumeTranscript = false
    @State private var startWatchdog: Task<Void, Never>?
    /// Held so `onDisappear` can cancel it. Its grace sleep outlives a fast
    /// dismiss otherwise, and `deliver` then hands a transcript to a page
    /// that is already gone.
    @State private var finalizeTask: Task<Void, Never>?
    @State private var showPermissionDenied = false
    @State private var showSTTError = false

    /// Driven by the tap, not derived from `speechService.isRecording`.
    /// `isRecording` only flips true once permission, asset checks and the
    /// analyzer have all come up, so a derived pill reads idle through the
    /// entire start and invites a second tap — which used to race a second
    /// engine onto the same analyzer.
    private enum Phase {
        case idle, starting, listening, transcribing
    }

    /// 56pt minimum; width hugs the glyph, then the timer while listening.
    private static let stateChange: Animation = .easeOut(duration: 0.25)
    /// Finalization normally lands well inside this. The net exists so a
    /// silent analyzer cannot strand the pill in `.transcribing`.
    private static let finalizeGrace: Duration = .milliseconds(1800)
    /// Generous, because a first run may be downloading a transcription model.
    /// It is a backstop against `startRecording` never returning at all, which
    /// would otherwise leave a spinner the user cannot dismiss.
    private static let startTimeout: Duration = .seconds(30)

    var body: some View {
        Button(action: toggle) {
            label
                .padding(.horizontal, 12)
                .mementoFooterGlassButtonChrome(interactive: interactive ?? !reduceMotion)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier("journal.entryEditor.mic")
        .onDisappear {
            startWatchdog?.cancel()
            startWatchdog = nil
            finalizeTask?.cancel()
            finalizeTask = nil
        }
        .onChange(of: speechService.isRecording) { wasRecording, isRecording in
            guard speechService.isOwner(ownerId) else { return }
            if isRecording {
                didConsumeTranscript = false
                setPhase(.listening)
            } else if wasRecording {
                // Covers the stop tap and the silence auto-stop alike.
                if speechService.isProcessing {
                    setPhase(.transcribing)
                } else {
                    deliver(speechService.bestAvailableTranscript)
                }
            }
        }
        .onChange(of: speechService.transcribedText) { _, transcript in
            guard speechService.isOwner(ownerId),
                  !transcript.isEmpty,
                  !speechService.isRecording
            else { return }
            deliver(transcript)
        }
        .onChange(of: speechService.isProcessing) { _, isProcessing in
            guard speechService.isOwner(ownerId),
                  !isProcessing,
                  !speechService.isRecording
            else { return }
            deliver(speechService.bestAvailableTranscript)
        }
        .onChange(of: speechService.activeSessionOwner) { _, owner in
            // Another surface took the mic, or the editor cancelled the
            // session on dismiss. Either way the pill must not stay lit.
            // `.starting` is excluded: ownership is still being claimed there.
            guard owner != ownerId,
                  phase == .listening || phase == .transcribing
            else { return }
            setPhase(.idle)
        }
        .alert("Microphone Access Required", isPresented: $showPermissionDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Memento needs microphone access to transcribe your voice. Enable it in Settings > Privacy > Microphone.")
        }
        .alert("Recording Failed", isPresented: $showSTTError) {
            Button("Try Again") { start() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(speechService.errorMessage ?? "Unable to start recording. Please try again.")
        }
    }

    // MARK: - Label

    @ViewBuilder
    private var label: some View {
        switch phase {
        case .idle:
            glyph("mic.fill", tint: foreground)
        case .starting, .transcribing:
            ProgressView()
                .tint(foreground)
        case .listening:
            HStack(spacing: 8) {
                glyph("stop.fill", tint: theme.destructive)
                Text(formatDuration(speechService.currentDuration))
                    .font(type.button)
                    .foregroundStyle(theme.destructive)
            }
        }
    }

    private func glyph(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(AppHeaderMetrics.controlSymbolFont)
            .foregroundStyle(tint)
    }

    // MARK: - Actions

    private func toggle() {
        switch phase {
        case .starting, .transcribing:
            // Work already in flight. Swallowing the tap here is what keeps a
            // second start from racing the first onto one analyzer.
            return
        case .idle:
            start()
        case .listening:
            stop()
        }
    }

    private func start() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        didConsumeTranscript = false
        setPhase(.starting)
        armStartWatchdog()

        Task { @MainActor in
            do {
                try await speechService.startRecording(ownerId: ownerId)
            } catch let error as SpeechService.SpeechError {
                setPhase(.idle)
                if case .permissionDenied = error {
                    showPermissionDenied = true
                } else {
                    showSTTError = true
                }
            } catch {
                setPhase(.idle)
                showSTTError = true
            }
        }
    }

    private func stop() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        setPhase(.transcribing)

        finalizeTask?.cancel()
        finalizeTask = Task { @MainActor in
            await speechService.stopRecording()
            // The observers hand off as soon as finalization reports. This is
            // only the net for when it never does.
            try? await Task.sleep(for: Self.finalizeGrace)
            guard !Task.isCancelled, !didConsumeTranscript else { return }
            deliver(speechService.bestAvailableTranscript)
        }
    }

    /// End the session and hand the transcript over, at most once.
    private func deliver(_ transcript: String) {
        guard !didConsumeTranscript else { return }
        didConsumeTranscript = true
        setPhase(.idle)

        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onTranscript(trimmed)
        }
        // Releases ownership too, so a stale observer cannot re-enter.
        //
        // Deferred one turn deliberately. Every caller but the finalize net is
        // an `onChange` handler, and `clearTranscription` writes four
        // `@Published` properties on the service this view observes — one of
        // them `activeSessionOwner`, which has an observer a few lines up.
        // Calling it inline republishes into the update that is still running,
        // which SwiftUI treats as undefined behavior and which can spin the
        // main thread. `didConsumeTranscript` is already latched above, so
        // nothing can slip through the gap.
        Task { @MainActor in
            speechService.clearTranscription()
        }
    }

    /// `startRecording` can stall indefinitely — an unavailable on-device
    /// transcription asset is the usual cause, and taps are swallowed in
    /// `.starting` so a second one cannot race a second engine. Without this
    /// the pill would spin forever with no way back.
    private func armStartWatchdog() {
        startWatchdog?.cancel()
        startWatchdog = Task { @MainActor in
            try? await Task.sleep(for: Self.startTimeout)
            guard !Task.isCancelled, phase == .starting else { return }
            await speechService.cancelRecording()
            setPhase(.idle)
            showSTTError = true
        }
    }

    private func setPhase(_ next: Phase) {
        guard phase != next else { return }
        if next != .starting {
            startWatchdog?.cancel()
            startWatchdog = nil
        }
        withAccessibleAnimation(Self.stateChange, reduceMotion: reduceMotion) {
            phase = next
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        switch phase {
        case .idle: return "Start voice recording"
        case .starting: return "Starting voice recording"
        case .listening: return "Stop recording"
        case .transcribing: return "Transcribing"
        }
    }

    private var accessibilityHint: String {
        switch phase {
        case .idle: return "Double-tap to record your voice"
        case .listening: return "Double-tap to stop and insert text"
        // VoiceOver skips an empty hint; neither transient phase is actionable.
        case .starting, .transcribing: return ""
        }
    }
}

#Preview("Editor Dictation Pill") {
    EditorDictationPill(
        ownerId: "Preview",
        foreground: .primary,
        onTranscript: { _ in }
    )
    .padding()
    .useTheme()
}
