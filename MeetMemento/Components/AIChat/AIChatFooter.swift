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
    var onSend: () -> Void
    var onNarrate: (() -> Void)?

    init(
        inputText: Binding<String>,
        isSending: Bool = false,
        onSend: @escaping () -> Void,
        onNarrate: (() -> Void)? = nil
    ) {
        self._inputText = inputText
        self.isSending = isSending
        self.onSend = onSend
        self.onNarrate = onNarrate
    }

    var body: some View {
        ChatInputField(
            text: $inputText,
            onSend: onSend,
            onNarrate: onNarrate,
            isInteractive: !isSending
        )
        // 16pt sides and 16pt above the field. Bottom offset is
        // `windowBottom + 16`, applied by AIChatView's scaffold.
        .padding(.horizontal, 16)
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
            onSend: { AppLogger.log("Send tapped") }
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
            onSend: { AppLogger.log("Send tapped") }
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
            onSend: { AppLogger.log("Send tapped") }
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
                onSend: {
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
