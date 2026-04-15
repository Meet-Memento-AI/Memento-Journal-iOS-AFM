import SwiftUI

// MARK: - Typography
// Default app typography uses Manrope for all text (headings, body, caption, micro).
// Use Typography.onboarding for onboarding screens (Lora Serif).

public struct Typography {

    // MARK: - Size Scale
    public let sizeXS: CGFloat = 11    // micro
    public let sizeSM: CGFloat = 13    // caption
    public let sizeMD: CGFloat = 14    // body2
    public let sizeLG: CGFloat = 16    // body1, h6, h5
    public let sizeXL: CGFloat = 20    // h4
    public let size2XL: CGFloat = 24   // h3
    public let size3XL: CGFloat = 32   // h2
    public let size4XL: CGFloat = 40   // h1

    // MARK: - Font Families (configurable for default vs onboarding)
    private let headingFontName: String
    private let bodyRegularFontName: String
    private let bodyMediumFontName: String
    private let bodySemiBoldFontName: String
    private let bodyBoldFontName: String

    // MARK: - Configurable Properties
    public let headingWeight: Font.Weight

    /// Default app typography: Manrope for all text.
    public init(headingWeight: Font.Weight = .semibold) {
        self.headingWeight = headingWeight
        self.headingFontName = "Manrope-Bold"
        self.bodyRegularFontName = "Manrope-Regular"
        self.bodyMediumFontName = "Manrope-Medium"
        self.bodySemiBoldFontName = "Manrope-SemiBold"
        self.bodyBoldFontName = "Manrope-Bold"
    }

    /// Internal init for custom font families (e.g. onboarding with Lora).
    private init(
        headingFontName: String,
        bodyRegularFontName: String,
        bodyMediumFontName: String,
        bodySemiBoldFontName: String,
        bodyBoldFontName: String,
        headingWeight: Font.Weight = .semibold
    ) {
        self.headingWeight = headingWeight
        self.headingFontName = headingFontName
        self.bodyRegularFontName = bodyRegularFontName
        self.bodyMediumFontName = bodyMediumFontName
        self.bodySemiBoldFontName = bodySemiBoldFontName
        self.bodyBoldFontName = bodyBoldFontName
    }

    /// Typography for onboarding screens: Lora Serif for headings and body.
    public static let onboarding: Typography = Typography(
        headingFontName: "Lora-SemiBold",
        bodyRegularFontName: "Lora-Regular",
        bodyMediumFontName: "Lora-Medium",
        bodySemiBoldFontName: "Lora-SemiBold",
        bodyBoldFontName: "Lora-Bold",
        headingWeight: .semibold
    )

    // MARK: - Line Spacing
    private func lineSpacing(for size: CGFloat) -> CGFloat { max(0, size * 0.5) }
    private func headingLineSpacing(for size: CGFloat) -> CGFloat { max(0, size * 0.2) }

    /// Line spacing for h4 (20pt) — 2px smaller than default heading spacing.
    public var h4LineSpacing: CGFloat { max(0, headingLineSpacing(for: sizeXL) - 2) }
    /// Line spacing for h5 (16pt) — 2px smaller than default heading spacing.
    public var h5LineSpacing: CGFloat { max(0, headingLineSpacing(for: sizeLG) - 2) }
    /// Line spacing for h6 (16pt) — 2px smaller than default heading spacing.
    public var h6LineSpacing: CGFloat { max(0, headingLineSpacing(for: sizeLG) - 2) }

    // Body text line spacing for body1/body2
    public var bodyLineSpacing: CGFloat { 4 }

    // MARK: - Font Helpers
    private func headingFont(size: CGFloat) -> Font {
        Font.custom(headingFontName, size: size, relativeTo: .title)
    }

    private func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold:
            return Font.custom(bodyBoldFontName, size: size, relativeTo: .body)
        case .semibold:
            return Font.custom(bodySemiBoldFontName, size: size, relativeTo: .body)
        case .medium:
            return Font.custom(bodyMediumFontName, size: size, relativeTo: .body)
        default:
            return Font.custom(bodyRegularFontName, size: size, relativeTo: .body)
        }
    }

    // MARK: - Headings (h1-h6) — Manrope Bold; Lora SemiBold for onboarding
    /// 40pt - Major display heading
    public var h1: Font { headingFont(size: size4XL) }
    /// 32pt - Secondary display heading
    public var h2: Font { headingFont(size: size3XL) }
    /// 24pt - Section heading
    public var h3: Font { headingFont(size: size2XL) }
    /// 20pt - Subsection heading
    public var h4: Font { headingFont(size: sizeXL) }
    /// 16pt - Minor heading
    public var h5: Font { headingFont(size: sizeLG) }
    /// 16pt bold (body weight) - Smallest heading
    public var h6: Font { bodyFont(size: sizeLG, weight: .bold) }

    // MARK: - Body Text (body1 = 16pt, body2 = 14pt)
    /// 16pt medium - Primary body text
    public var body1: Font { bodyFont(size: sizeLG, weight: .medium) }
    /// 16pt semibold - Emphasized body text
    public var body1Medium: Font { bodyFont(size: sizeLG, weight: .semibold) }
    /// 16pt bold - Strong body text
    public var body1Bold: Font { bodyFont(size: sizeLG, weight: .bold) }
    /// 14pt medium - Secondary body text
    public var body2: Font { bodyFont(size: sizeMD, weight: .medium) }
    /// 14pt semibold - Emphasized secondary text
    public var body2Medium: Font { bodyFont(size: sizeMD, weight: .semibold) }
    /// 14pt bold - Strong secondary text
    public var body2Bold: Font { bodyFont(size: sizeMD, weight: .bold) }

    // MARK: - Small Text (caption = 13pt, micro = 11pt)
    /// 13pt regular - Caption text
    public var caption: Font { bodyFont(size: sizeSM, weight: .regular) }
    /// 13pt medium - Emphasized caption
    public var captionMedium: Font { bodyFont(size: sizeSM, weight: .medium) }
    /// 13pt bold - Strong caption
    public var captionBold: Font { bodyFont(size: sizeSM, weight: .bold) }
    /// 11pt regular - Micro/fine print text
    public var micro: Font { bodyFont(size: sizeXS, weight: .regular) }
    /// 11pt medium - Emphasized micro text
    public var microMedium: Font { bodyFont(size: sizeXS, weight: .medium) }
    /// 11pt bold - Strong micro text
    public var microBold: Font { bodyFont(size: sizeXS, weight: .bold) }

    // MARK: - Utility Aliases
    /// Label text - uses captionMedium (13pt medium)
    public var label: Font { captionMedium }
    /// Label bold variant (13pt bold)
    public var labelBold: Font { captionBold }
    /// Button text - uses body1Bold (16pt bold)
    public var button: Font { body1Bold }
    /// Input field text - uses body1 (16pt regular)
    public var input: Font { body1 }

    // MARK: - Deprecated Aliases (for backward compatibility)
    @available(*, deprecated, renamed: "body1")
    public var body: Font { body1 }

    @available(*, deprecated, renamed: "body1Medium")
    public var bodyMedium: Font { body1Medium }

    @available(*, deprecated, renamed: "body1Bold")
    public var bodyBold: Font { body1Bold }

    @available(*, deprecated, renamed: "body2")
    public var bodySmall: Font { body2 }

    @available(*, deprecated, renamed: "body2Bold")
    public var bodySmallBold: Font { body2Bold }

    @available(*, deprecated, renamed: "caption")
    public var captionText: Font { caption }

    @available(*, deprecated, renamed: "micro")
    public var microText: Font { micro }

    // Deprecated size aliases
    @available(*, deprecated, renamed: "sizeXS")
    public var micro_size: CGFloat { sizeXS }

    @available(*, deprecated, renamed: "sizeSM")
    public var caption_size: CGFloat { sizeSM }

    @available(*, deprecated, renamed: "sizeMD")
    public var bodyS: CGFloat { sizeMD }

    @available(*, deprecated, renamed: "sizeLG")
    public var bodyL: CGFloat { sizeLG }

    @available(*, deprecated, renamed: "sizeLG")
    public var titleXS: CGFloat { sizeLG }

    @available(*, deprecated, renamed: "sizeXL")
    public var titleS: CGFloat { sizeXL }

    @available(*, deprecated, renamed: "size2XL")
    public var titleM: CGFloat { size2XL }

    @available(*, deprecated, renamed: "size3XL")
    public var displayL: CGFloat { size3XL }

    @available(*, deprecated, renamed: "size4XL")
    public var displayXL: CGFloat { size4XL }

    // MARK: - Line Height Modifiers
    public func lineSpacingModifier(for size: CGFloat) -> some ViewModifier {
        LineHeight(spacing: lineSpacing(for: size))
    }

    public func headingLineSpacingModifier(for size: CGFloat) -> some ViewModifier {
        LineHeight(spacing: headingLineSpacing(for: size))
    }

    struct LineHeight: ViewModifier {
        let spacing: CGFloat
        func body(content: Content) -> some View {
            content.lineSpacing(spacing)
        }
    }
}

// MARK: - Environment + Defaults
private struct TypographyKey: EnvironmentKey {
    static let defaultValue = Typography()
}

public extension EnvironmentValues {
    var typography: Typography {
        get { self[TypographyKey.self] }
        set { self[TypographyKey.self] = newValue }
    }
}

public struct TypographyProvider: ViewModifier {
    let typography: Typography
    public init(_ typography: Typography = Typography()) {
        self.typography = typography
    }
    public func body(content: Content) -> some View {
        content.environment(\.typography, typography)
    }
}

public extension View {
    func useTypography(_ typography: Typography = Typography()) -> some View {
        modifier(TypographyProvider(typography))
    }
}

// MARK: - Sugar Extensions
public extension View {
    func h1(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.h1)
            .modifier(env.typography.headingLineSpacingModifier(for: env.typography.size4XL))
    }
    func h2(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.h2)
            .modifier(env.typography.headingLineSpacingModifier(for: env.typography.size3XL))
    }
    func h3(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.h3)
            .modifier(env.typography.headingLineSpacingModifier(for: env.typography.size2XL))
    }
    func h4(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.h4)
            .lineSpacing(env.typography.h4LineSpacing)
    }
    func h5(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.h5)
            .lineSpacing(env.typography.h5LineSpacing)
    }
    func h6(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.h6)
            .lineSpacing(env.typography.h6LineSpacing)
    }
    func bodyText(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.body1)
            .lineSpacing(env.typography.bodyLineSpacing)
    }
    func labelText(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.label)
            .modifier(env.typography.lineSpacingModifier(for: env.typography.sizeSM))
    }
    func buttonText(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.button)
            .modifier(env.typography.lineSpacingModifier(for: env.typography.sizeLG))
    }
    func inputText(_ env: EnvironmentValues) -> some View {
        self.font(env.typography.input)
            .modifier(env.typography.lineSpacingModifier(for: env.typography.sizeLG))
    }
}

// MARK: - Header Gradient Extension
struct HeaderGradientModifier: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View {
        content.foregroundStyle(
            LinearGradient(
                gradient: Gradient(colors: [theme.headerGradientStart, theme.headerGradientEnd]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

public extension View {
    func headerGradient() -> some View {
        self.modifier(HeaderGradientModifier())
    }
}
