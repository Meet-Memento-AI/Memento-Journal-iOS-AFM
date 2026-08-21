import SwiftUI

public struct PrimaryButton: View {
    public enum ImagePlacement {
        case leading
        case trailing
    }

    @Environment(\.theme) private var theme

    let title: String
    var systemImage: String? = nil
    var imagePlacement: ImagePlacement = .leading
    var isLoading: Bool = false
    var action: () -> Void

    public init(title: String,
                systemImage: String? = nil,
                imagePlacement: ImagePlacement = .leading,
                isLoading: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.imagePlacement = imagePlacement
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button {
            guard !isLoading else { return }
            action()
        } label: {
            HStack(spacing: Spacing.xxs) {
                if let systemImage, imagePlacement == .leading {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .typographyH5()
                if let systemImage, imagePlacement == .trailing {
                    Image(systemName: systemImage)
                }
                if isLoading { ProgressView().tint(theme.primaryForeground) }
            }
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .foregroundStyle(theme.primaryForeground)
            .background(theme.primary)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.button, style: .continuous))
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
        PrimaryButton(title: "Next step", systemImage: "arrow.right", imagePlacement: .trailing) {}
        PrimaryButton(title: "Save", isLoading: true) {}
    }
    .padding()
    .useTheme()
    .useTypography()
}

#Preview("Dark") {
    VStack(spacing: 12) {
        PrimaryButton(title: "Reflect", systemImage: "sparkles") {}
        PrimaryButton(title: "Next step", systemImage: "arrow.right", imagePlacement: .trailing) {}
        PrimaryButton(title: "Save", isLoading: true) {}
    }
    .padding()
    .useTheme()
    .useTypography()
    .preferredColorScheme(.dark)
}
