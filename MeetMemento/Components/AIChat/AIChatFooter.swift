//
//  AIChatFooter.swift
//  MeetMemento
//
//  Footer wrapper for AI Chat interface
//  Wraps ChatInputField with proper padding
//

import SwiftUI

struct AIChatFooter: View {
    @Binding var inputText: String
    var isSending: Bool
    var onSend: () -> Void
    var hasExistingChats: Bool
    var onHistoryTap: (() -> Void)?
    var onNarrateStateChange: ((Bool) -> Void)?

    @Environment(\.theme) private var theme

    init(
        inputText: Binding<String>,
        isSending: Bool = false,
        onSend: @escaping () -> Void,
        hasExistingChats: Bool = false,
        onHistoryTap: (() -> Void)? = nil,
        onNarrateStateChange: ((Bool) -> Void)? = nil
    ) {
        self._inputText = inputText
        self.isSending = isSending
        self.onSend = onSend
        self.hasExistingChats = hasExistingChats
        self.onHistoryTap = onHistoryTap
        self.onNarrateStateChange = onNarrateStateChange
    }

    var body: some View {
        ChatInputField(
            text: $inputText,
            onSend: onSend,
            onHistoryTap: onHistoryTap,
            onNarrateStateChange: onNarrateStateChange,
            isInteractive: !isSending,
            hasExistingChats: hasExistingChats
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

#Preview("AIChatFooter - With History") {
    VStack {
        Spacer()
        AIChatFooter(
            inputText: .constant(""),
            onSend: { AppLogger.log("Send tapped") },
            hasExistingChats: true,
            onHistoryTap: { AppLogger.log("History tapped") }
        )
    }
    .useTheme()
    .useTypography()
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
