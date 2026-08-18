import SwiftUI

public struct SecondaryButton: View {
    @Environment(\.theme) private var theme

    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var customColor: Color? = nil
    var action: () -> Void

    public init(title: String,
                systemImage: String? = nil,
                isLoading: Bool = false,
                customColor: Color? = nil,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.customColor = customColor
        self.action = action
    }

    // Determine if we're in dark mode variant (white text on dark bg)
    private var isDarkVariant: Bool {
        customColor == .white
    }

    public var body: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                    .typographyH5()
                if isLoading { ProgressView().tint(customColor ?? theme.foreground) }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .foregroundStyle(customColor ?? theme.foreground)
            .background(isDarkVariant ? Color.white.opacity(0.15) : theme.muted)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous)
                    .stroke(isDarkVariant ? Color.white.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(SecondaryButtonPressStyle())
    }
}

// MARK: - Button Press Style

struct SecondaryButtonPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview("Light") {
    VStack(spacing: 12) {
        SecondaryButton(title: "Reflect", systemImage: "sparkles") {}
        SecondaryButton(title: "Save", isLoading: true) {}
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Dark") {
    VStack(spacing: 12) {
        SecondaryButton(title: "Reflect", systemImage: "sparkles") {}
        SecondaryButton(title: "Save", isLoading: true) {}
    }
    .padding()
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}

#Preview("Dark Variant (On Primary Background)") {
    VStack(spacing: 12) {
        SecondaryButton(title: "Create Account", customColor: .white) {}
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
        LinearGradient(
            colors: [PrimaryScale.primary900, GrayScale.gray900],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
    .useTheme()
    .useTypography()
}
