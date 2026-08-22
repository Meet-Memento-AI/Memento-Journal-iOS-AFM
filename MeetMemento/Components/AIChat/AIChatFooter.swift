//
//  AIChatFooter.swift
//  MeetMemento
//
//  Footer wrapper for AI Chat interface.
//  Wraps ChatInputField with proper padding — and nothing else. Chat history
//  moved out to TopNavHeader's trailing slot, and dictation now renders inside
//  the field itself, so this is a pure layout shim.
//

import SwiftUI

struct AIChatFooter: View {
    @Binding var inputText: String
    var isSending: Bool
    var onSend: ([Data]) -> Void
    var onNarrate: (() -> Void)?
    /// Forwarded to `ChatInputField` so the send choreography can read the
    /// composer's pre-send frame.
    var onComposerFrame: ((CGRect) -> Void)?

    init(
        inputText: Binding<String>,
        isSending: Bool = false,
        onSend: @escaping ([Data]) -> Void,
        onNarrate: (() -> Void)? = nil,
        onComposerFrame: ((CGRect) -> Void)? = nil
    ) {
        self._inputText = inputText
        self.isSending = isSending
        self.onSend = onSend
        self.onNarrate = onNarrate
        self.onComposerFrame = onComposerFrame
    }

    var body: some View {
        ChatInputField(
            text: $inputText,
            onSend: onSend,
            onNarrate: onNarrate,
            isInteractive: !isSending,
            onComposerFrame: onComposerFrame
        )
        // 16pt above the field. Horizontal inset is `rootEdgeInset()` on the
        // capsule, applied before glass. Bottom offset is applied by
        // AIChatView's scaffold: `windowBottom + 16` at rest, `keyboardHeight
        // + 16` with the keyboard up so the capsule never sits on the keys.
        .padding(.top, 16)
        .opacity(isSending ? 0.7 : 1.0)
    }
}

// MARK: - Previews

#Preview("AIChatFooter - Default") {
    VStack {
        Spacer()
        AIChatFooter(
            inputText: .constant(""),
            onSend: { _ in AppLogger.log("Send tapped") }
        )
    }
    .useTheme()
    .useTypography()
}

#Preview("AIChatFooter - Sending") {
    VStack {
        Spacer()
        AIChatFooter(
            inputText: .constant("What patterns do you see?"),
            isSending: true,
            onSend: { _ in AppLogger.log("Send tapped") }
        )
    }
    .useTheme()
    .useTypography()
}

#Preview("AIChatFooter - Dark Mode") {
    VStack {
        Spacer()
        AIChatFooter(
            inputText: .constant(""),
            onSend: { _ in AppLogger.log("Send tapped") }
        )
    }
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}

#Preview("AIChatFooter - Interactive") {
    AIChatFooterInteractivePreview()
        .useTheme()
        .useTypography()
}

private struct AIChatFooterInteractivePreview: View {
    @State private var inputText = ""
    @State private var isSending = false

    var body: some View {
        VStack {
            Spacer()

            Text("Tap buttons to see state changes")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)

            AIChatFooter(
                inputText: $inputText,
                isSending: isSending,
                onSend: { _ in
                    isSending = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isSending = false
                        inputText = ""
                    }
                }
            )
        }
    }
}
