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
    /// Optional caption above the field (Figma Input-Field).
    var label: String? = nil
    /// Filled well matching Figma Input (`neutral/100`, 12pt radius).
    var isFilled: Bool = false

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type
    @FocusState private var isFocused: Bool

    public init(
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        textInputAutocapitalization: TextInputAutocapitalization = .sentences,
        label: String? = nil,
        isFilled: Bool = false
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.textInputAutocapitalization = textInputAutocapitalization
        self.label = label
        self.isFilled = isFilled
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let label {
                Text(label)
                    .font(type.body2Bold)
                    .foregroundStyle(theme.foreground)
                    .accessibilityHidden(true)
            }

            field
        }
    }

    private var field: some View {
        Group {
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .font(isFilled ? type.body2Medium : type.h4)
        .foregroundStyle(theme.foreground)
        .textInputAutocapitalization(textInputAutocapitalization)
        .keyboardType(keyboardType)
        .focused($isFocused)
        .accessibilityLabel(placeholder)
        .accessibilityHint(isSecure ? "Secure text field" : "Text field")
        .padding(.horizontal, isFilled ? Spacing.md : Spacing.xs)
        .padding(.vertical, isFilled ? Spacing.sm : 14)
        .frame(maxWidth: isFilled ? .infinity : nil, alignment: .leading)
        .background {
            if isFilled {
                RoundedRectangle(cornerRadius: theme.radius.md, style: .continuous)
                    .fill(theme.cardBackground)
            }
        }
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

        AppTextField(
            placeholder: "First name",
            text: .constant(""),
            textInputAutocapitalization: .words,
            label: "First name",
            isFilled: true
        )
    }
    .padding()
    .useTheme()
    .useTypography()
    .background(Environment(\.theme).wrappedValue.background)
}

