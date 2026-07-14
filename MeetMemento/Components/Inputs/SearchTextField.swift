//
//  SearchTextField.swift
//  MeetMemento
//
//  Reusable search text field component for search overlays
//

import SwiftUI

struct SearchTextField: View {
    @Binding var text: String
    var placeholder: String = "Search journal entries"
    var onCancel: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Search field with icon
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(type.body1)
                    .foregroundStyle(isFocused ? theme.primary : theme.mutedForeground)

                TextField(placeholder, text: $text)
                    .font(type.input)
                    .foregroundStyle(theme.foreground)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .submitLabel(.search)
                    .accessibilityLabel(placeholder)

                // Clear button
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(type.body2)
                            .foregroundStyle(theme.mutedForeground)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(theme.inputBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                    .stroke(isFocused ? theme.primary : .clear, lineWidth: 2)
            )

            // Cancel button
            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .typographyBody2()
                    .foregroundStyle(theme.primary)
            }
            .accessibilityLabel("Cancel search")
        }
        .onAppear {
            // Auto-focus the search field
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                isFocused = true
            }
        }
    }
}

// MARK: - Previews

#Preview("SearchTextField - Empty") {
    VStack {
        SearchTextField(
            text: .constant(""),
            onCancel: { AppLogger.log("Cancelled") }
        )
        .padding()
    }
    .background(Environment(\.theme).wrappedValue.background)
    .useTheme()
    .useTypography()
}

#Preview("SearchTextField - With Text") {
    VStack {
        SearchTextField(
            text: .constant("morning reflection"),
            onCancel: { AppLogger.log("Cancelled") }
        )
        .padding()
    }
    .background(Environment(\.theme).wrappedValue.background)
    .useTheme()
    .useTypography()
}

#Preview("SearchTextField - Dark Mode") {
    VStack {
        SearchTextField(
            text: .constant(""),
            onCancel: { AppLogger.log("Cancelled") }
        )
        .padding()
    }
    .preferredColorScheme(.dark)
    .useTheme()
    .useTypography()
}
