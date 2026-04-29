import SwiftUI

public struct PrimaryButton: View {
    @Environment(\.theme) private var theme

    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var action: () -> Void

    public init(title: String,
                systemImage: String? = nil,
                isLoading: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
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
                if isLoading { ProgressView().tint(theme.primaryForeground) }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(theme.primaryForeground)
            .background(theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.xl, style: .continuous))
        }
        .buttonStyle(PrimaryButtonPressStyle())
    }
}

// MARK: - Button Press Style

struct PrimaryButtonPressStyle: ButtonStyle {
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
        PrimaryButton(title: "Reflect", systemImage: "sparkles") {}
        PrimaryButton(title: "Save", isLoading: true) {}
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Dark") {
    VStack(spacing: 12) {
        PrimaryButton(title: "Reflect", systemImage: "sparkles") {}
        PrimaryButton(title: "Save", isLoading: true) {}
    }
    .padding()
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
