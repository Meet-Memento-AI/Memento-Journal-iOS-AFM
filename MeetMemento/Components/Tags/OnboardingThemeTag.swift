import SwiftUI

/// Minimal theme-aware tag (large rounded chip with bold text).
/// Toggleable component with two states:
/// - Unselected: transparent background with gray/200 border
/// - Selected: gray/200 background
/// Uses Theme + Typography tokens. Binding-driven for AI tuning.
public struct OnboardingThemeTag: View {
    public let text: String
    @Binding public var isSelected: Bool

    @Environment(\.theme) private var theme
    @Environment(\.typography) private var type

    public init(_ text: String, isSelected: Binding<Bool>) {
        self.text = text
        self._isSelected = isSelected
    }

    public var body: some View {
        Button {
            // Toggle selection state with haptic feedback
            isSelected.toggle()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Text(text)
                .font(type.body1Bold)
                .modifier(type.lineSpacingModifier(for: type.sizeLG))
                .foregroundStyle(theme.foreground) // token: high-contrast text
                .frame(maxWidth: .infinity) // Allow full width stretch
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? theme.muted : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.muted, lineWidth: isSelected ? 0 : 1.5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain) // Remove default button styling
        .accessibilityLabel(Text(text))
        .accessibilityAddTraits([.isButton])
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

// MARK: - Previews

#Preview("Light - Interactive") {
    OnboardingThemeTagPreview()
        .useTheme()
        .useTypography()
}

#Preview("Dark - Interactive") {
    OnboardingThemeTagPreview()
        .environment(\.colorScheme, .dark)
        .useTheme()
        .useTypography()
        .background(Color.black)
}

// Preview wrapper for interactive state
private struct OnboardingThemeTagPreview: View {
    @State private var selection1 = false
    @State private var selection2 = true
    @State private var selection3 = false

    var body: some View {
        VStack(spacing: 24) {
            OnboardingThemeTag("Work related stress", isSelected: $selection1)
                .frame(maxWidth: .infinity)
            OnboardingThemeTag("Morning routine", isSelected: $selection2)
                .frame(maxWidth: .infinity)
            OnboardingThemeTag("Deadlines", isSelected: $selection3)
                .frame(maxWidth: .infinity)

            Divider()

            Text("Selected tags:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(selectedTags)
                .font(.caption)
                .foregroundStyle(.primary)
        }
        .padding(24)
    }

    private var selectedTags: String {
        var tags: [String] = []
        if selection1 { tags.append("Work related stress") }
        if selection2 { tags.append("Morning routine") }
        if selection3 { tags.append("Deadlines") }
        return tags.isEmpty ? "None" : tags.joined(separator: ", ")
    }
}
