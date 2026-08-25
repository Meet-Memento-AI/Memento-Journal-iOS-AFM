import SwiftUI
import UIKit

// MARK: - Typography
// Default app typography uses Lora for h1/h2 (display) and Figtree for
// h3–h6, body, caption, and micro. Use Typography.onboarding for
// onboarding screens (Lora throughout).
// All sizes support Dynamic Type scaling via @ScaledMetric.

public struct Typography {

    // MARK: - Base Size Scale (used as relativeTo base values)
    // These are the design-time base sizes before Dynamic Type scaling
    public static let baseSizeXS: CGFloat = 11    // micro
    public static let baseSizeSM: CGFloat = 13    // caption
    public static let baseSizeMD: CGFloat = 14    // body2
    public static let baseSizeLG: CGFloat = 16    // body1, h6, h5
    public static let baseSizeXL: CGFloat = 20    // h4
    public static let baseSize2XL: CGFloat = 24   // h3
    public static let baseSize3XL: CGFloat = 32   // h2
    public static let baseSize4XL: CGFloat = 40   // h1

    // MARK: - Size Scale (legacy accessors for backward compatibility)
    public var sizeXS: CGFloat { Self.baseSizeXS }
    public var sizeSM: CGFloat { Self.baseSizeSM }
    public var sizeMD: CGFloat { Self.baseSizeMD }
    public var sizeLG: CGFloat { Self.baseSizeLG }
    public var sizeXL: CGFloat { Self.baseSizeXL }
    public var size2XL: CGFloat { Self.baseSize2XL }
    public var size3XL: CGFloat { Self.baseSize3XL }
    public var size4XL: CGFloat { Self.baseSize4XL }

    // MARK: - Font Families (configurable for default vs onboarding)
    /// Display face for h1/h2 only. Lora (serif) in both the default and the
    /// onboarding scale — the two largest sizes carry the brand voice, while
    /// h3 and below stay on the sans `headingFontName` so section headers keep
    /// matching body copy.
    private let displayFontName: String
    private let headingFontName: String
    private let bodyRegularFontName: String
    private let bodyMediumFontName: String
    private let bodySemiBoldFontName: String
    private let bodyBoldFontName: String

    // MARK: - Configurable Properties
    public let headingWeight: Font.Weight

    /// Default app typography: Lora for the h1/h2 display sizes, Figtree for
    /// everything else (h3–h6, body, caption).
    public init(headingWeight: Font.Weight = .semibold) {
        self.headingWeight = headingWeight
        self.displayFontName = "Lora-Bold"
        self.headingFontName = "Figtree-Bold"
        self.bodyRegularFontName = "Figtree-Regular"
        self.bodyMediumFontName = "Figtree-Medium"
        self.bodySemiBoldFontName = "Figtree-SemiBold"
        self.bodyBoldFontName = "Figtree-Bold"
    }

    /// Internal init for custom font families (e.g. onboarding with Lora).
    private init(
        displayFontName: String,
        headingFontName: String,
        bodyRegularFontName: String,
        bodyMediumFontName: String,
        bodySemiBoldFontName: String,
        bodyBoldFontName: String,
        headingWeight: Font.Weight = .semibold
    ) {
        self.headingWeight = headingWeight
        self.displayFontName = displayFontName
        self.headingFontName = headingFontName
        self.bodyRegularFontName = bodyRegularFontName
        self.bodyMediumFontName = bodyMediumFontName
        self.bodySemiBoldFontName = bodySemiBoldFontName
        self.bodyBoldFontName = bodyBoldFontName
    }

    /// Typography for onboarding screens: Lora Serif for headings and body.
    public static let onboarding: Typography = Typography(
        displayFontName: "Lora-Bold",
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

    /// Extra SwiftUI `.lineSpacing` so the line box is 150% of `size`
    /// (`size * 1.5 - UIFont.lineHeight`). SwiftUI's value is the gap
    /// *above* the font's built-in line height, not CSS `line-height`.
    public func bodyLineSpacing(for size: CGFloat) -> CGFloat {
        let font = UIFont(name: bodyMediumFontName, size: size)
            ?? .systemFont(ofSize: size)
        return max(0, size * 1.5 - font.lineHeight)
    }

    /// Body1 (16pt) line spacing — 24pt line box.
    public var bodyLineSpacing: CGFloat { bodyLineSpacing(for: sizeLG) }

    // MARK: - Font Helpers
    /// h1/h2 only — the serif display face.
    private func displayFont(size: CGFloat) -> Font {
        Font.custom(displayFontName, size: size, relativeTo: .title)
    }

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

    // MARK: - Headings (h1-h6)
    // h1/h2 are Lora Bold (the display face); h3-h5 are Figtree Bold, or
    // Lora SemiBold throughout in the onboarding scale.
    /// 40pt - Major display heading
    public var h1: Font { displayFont(size: size4XL) }
    /// 32pt - Secondary display heading
    public var h2: Font { displayFont(size: size3XL) }
    /// 24pt - Section heading
    public var h3: Font { headingFont(size: size2XL) }
    /// 20pt - Subsection heading
    public var h4: Font { headingFont(size: sizeXL) }
    /// 20pt semibold — one weight below `h4` (Figtree Bold)
    public var h4Medium: Font { bodyFont(size: sizeXL, weight: .semibold) }
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
    /// 18pt medium - chat composer placeholder and field text (Figma 433:1077).
    /// Sits between body1 (16) and h4 (20); the composer is the only surface
    /// that asks for it, so it lives here rather than in the size scale.
    public var inputLarge: Font { bodyFont(size: 18, weight: .medium) }
    /// 18pt bold — suggestion-card prompt (Figma 709:2320).
    public var promptTitle: Font { bodyFont(size: 18, weight: .bold) }

    /// 16pt Figtree Medium — loading-state heading (chat thinking row).
    public var loadingHeading: Font {
        bodyFont(size: sizeLG, weight: .medium)
    }

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

// MARK: - Dynamic Type Support

/// A property wrapper that scales typography sizes according to Dynamic Type settings.
/// Use with SwiftUI views to support accessibility text scaling up to 200%.
@propertyWrapper
public struct ScaledTypographySize: DynamicProperty {
    @ScaledMetric private var scaledValue: CGFloat

    public var wrappedValue: CGFloat { scaledValue }

    public init(baseSize: CGFloat, relativeTo textStyle: Font.TextStyle = .body) {
        _scaledValue = ScaledMetric(wrappedValue: baseSize, relativeTo: textStyle)
    }
}

/// Dynamic Type-aware typography sizes that scale with user preferences.
/// Use these in views that need to respond to Dynamic Type changes.
public struct ScaledTypography {
    @ScaledMetric(relativeTo: .caption2) public var sizeXS: CGFloat = Typography.baseSizeXS
    @ScaledMetric(relativeTo: .caption) public var sizeSM: CGFloat = Typography.baseSizeSM
    @ScaledMetric(relativeTo: .subheadline) public var sizeMD: CGFloat = Typography.baseSizeMD
    @ScaledMetric(relativeTo: .body) public var sizeLG: CGFloat = Typography.baseSizeLG
    @ScaledMetric(relativeTo: .title3) public var sizeXL: CGFloat = Typography.baseSizeXL
    @ScaledMetric(relativeTo: .title2) public var size2XL: CGFloat = Typography.baseSize2XL
    @ScaledMetric(relativeTo: .title) public var size3XL: CGFloat = Typography.baseSize3XL
    @ScaledMetric(relativeTo: .largeTitle) public var size4XL: CGFloat = Typography.baseSize4XL

    public init() {}
}

// MARK: - Dynamic Type View Modifier

/// Modifier that limits Dynamic Type scaling to prevent layout overflow.
/// Restricts maximum size to xxxLarge (roughly 200% of default).
public struct DynamicTypeLimitModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

public extension View {
    /// Limits Dynamic Type scaling to xxxLarge to prevent layout overflow.
    /// Apply at the root of screens or components that may overflow at extreme sizes.
    func limitDynamicTypeSize() -> some View {
        modifier(DynamicTypeLimitModifier())
    }
}

// MARK: - Accessibility Text Scaling Environment

/// Environment key to check if the user has enabled larger accessibility sizes.
private struct IsAccessibilitySizeEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Returns true if the user has enabled accessibility text sizes (xxxLarge or larger).
    var isAccessibilitySizeEnabled: Bool {
        get { self[IsAccessibilitySizeEnabledKey.self] }
        set { self[IsAccessibilitySizeEnabledKey.self] = newValue }
    }
}

/// Modifier that tracks accessibility size preference and updates environment.
public struct AccessibilitySizeTracker: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public func body(content: Content) -> some View {
        content
            .environment(\.isAccessibilitySizeEnabled, dynamicTypeSize >= .accessibility1)
    }
}

public extension View {
    /// Tracks whether user has enabled accessibility text sizes.
    /// Provides `isAccessibilitySizeEnabled` environment value downstream.
    func trackAccessibilitySize() -> some View {
        modifier(AccessibilitySizeTracker())
    }
}
