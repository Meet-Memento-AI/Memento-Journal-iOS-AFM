import SwiftUI

/// Minimal theme-aware tag (large rounded chip with bold text).
/// Uses Theme + Typography tokens only. Supports optional onClick interaction.
public struct ThemeTag: View {
    public let text: String
    public var onClick: (() -> Void)?

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(_ text: String, onClick: (() -> Void)? = nil) {
        self.text = text
        self.onClick = onClick
    }

    public var body: some View {
        // Simple tag with muted background, bold sans text, rounded corners.
        // No border for a cleaner look.
        Button {
            onClick?()
        } label: {
            Text(text)
                .font(type.body1Bold) // Manrope Bold from Typography.swift
                .modifier(type.lineSpacingModifier(for: type.sizeLG))
                .foregroundStyle(theme.foreground) // token: high-contrast text
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.muted) // Use semantic token for light/dark support
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain) // Remove default button styling
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits(onClick != nil ? [.isButton] : [])
    }
}

// MARK: - Previews

#Preview("Light") {
    VStack(spacing: 24) {
        ThemeTag("Work related stress") {
            print("Tapped: Work related stress")
        }
        ThemeTag("Morning routine") {
            print("Tapped: Morning routine")
        }
        ThemeTag("Deadlines") {
            print("Tapped: Deadlines")
        }
    }
    .padding(24)
    .useTheme()
    .useTypography()
}

#Preview("Dark") {
    VStack(spacing: 24) {
        ThemeTag("Work related stress") {
            print("Tapped: Work related stress")
        }
        ThemeTag("Morning routine") {
            print("Tapped: Morning routine")
        }
        ThemeTag("Deadlines") {
            print("Tapped: Deadlines")
        }
    }
    .padding(24)
    .environment(\.colorScheme, .dark)
    .useTheme()
    .useTypography()
    .background(Color.black)
}
