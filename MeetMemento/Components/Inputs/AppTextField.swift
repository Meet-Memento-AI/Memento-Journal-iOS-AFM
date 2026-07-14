//
//  AppTextField.swift
//  MeetMemento
//
//  Reusable text field component following app design system
//

import SwiftUI

public struct AppTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textInputAutocapitalization: TextInputAutocapitalization = .sentences

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @FocusState private var isFocused: Bool

    public init(
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textInputAutocapitalization: TextInputAutocapitalization = .sentences
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.textInputAutocapitalization = textInputAutocapitalization
    }

    public var body: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(type.h4)
        .foregroundStyle(theme.foreground) // Use semantic theme color for proper contrast
        .textInputAutocapitalization(textInputAutocapitalization)
        .keyboardType(keyboardType)
        .focused($isFocused)
        .accessibilityLabel(placeholder)
        .accessibilityHint(isSecure ? "Secure text field" : "Text field")
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 14)
    }
}

#Preview {
    VStack(spacing: 16) {
        AppTextField(
            placeholder: "Email",
            text: .constant(""),
            keyboardType: .emailAddress,
            textInputAutocapitalization: .never
        )

        AppTextField(
            placeholder: "Password",
            text: .constant("test@example.com"),
            isSecure: true
        )
    }
    .padding()
    .useTheme()
    .useTypography()
    .background(Environment(\.theme).wrappedValue.background)
}

