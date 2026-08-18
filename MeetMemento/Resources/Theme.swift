import SwiftUI

// MARK: - Hex helpers
extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255.0
            g = Double((v >> 8)  & 0xFF) / 255.0
            b = Double(v & 0xFF) / 255.0
        default:
            r = 1; g = 1; b = 1
        }
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - Design Tokens
/// Design token system for consistent color usage throughout the app.
/// These tokens provide a structured color palette with defined scales for gray and primary colors.
///
/// ## WCAG 2.1 AA Contrast Requirements
/// - Normal text (< 18pt or < 14pt bold): 4.5:1 minimum
/// - Large text (≥ 18pt or ≥ 14pt bold): 3:1 minimum
/// - UI components and graphics: 3:1 minimum
///
/// ## Verified Contrast Ratios (Light Mode)
/// Measured 2026-08-17 against the B&W canvas + ink buttons, not carried over.
/// - foreground (#000000) on background (#FFFFFF): 21.00:1 ✓
/// - mutedForeground (gray600 #525252) on background: 7.78:1 ✓
/// - white on primary / primary900 (#2C1E19): 16.08:1 ✓ (filled buttons)
/// - accent (brand #A87549) on background, as UI/icon: 3.96:1 ✓ (3:1 floor)
/// - brandOnText (#895C37) on background, as text: 5.75:1 ✓
///
/// ## Verified Contrast Ratios (Dark Mode)
/// - foreground (#FFFFFF) on background (#000000): 21.00:1 ✓
/// - mutedForeground (gray400 #A3A3A3) on background: 8.36:1 ✓
/// - black on primary (#FFFFFF): 21.00:1 ✓ (filled buttons)
/// - accent (brandDark #C89A6E) on background: 8.28:1 ✓
///
/// ## Low Contrast Warning - Use with caution
/// - overlayTextSecondary (mutedForeground): fine as secondary copy; not a
///   disabled-control colour
/// - glassBorder: decorative hairline only, not critical info
/// - **accent (#A87549) must never carry small text.** It is 3.96:1 against
///   white — fine as a fill or icon, below AA as text. Use
///   `BrandColors.brandOnText` wherever brown *is* text.
/// - gray500 (#737373) is 4.75:1 on white — AA for normal text, but keep it
///   off tiny captions when possible.
///
/// ## Correction
/// The pre-cordovan header claimed dark `primary400` on `gray900` was 5.2:1.
/// Re-measuring the old purple gives **4.02:1** — it was already failing AA.
/// These ratios were never machine-verified (see specs/012 §4); the numbers
/// above were computed directly from the hex values in this file.

/// Neutral scale — cool greys for canvas, wells, and hairlines. `gray800` /
/// `gray900` stay warm ink so leftover fill call sites match the darkest
/// brown used for filled buttons. Kept under the name `GrayScale` because
/// ~40 call sites depend on it.
struct GrayScale {
    static let gray50  = Color(hex: "#FFFFFF") // canvas
    static let gray100 = Color(hex: "#F5F5F5") // surface-sunken
    static let gray200 = Color(hex: "#E5E5E5") // border
    static let gray300 = Color(hex: "#D4D4D4") // border-strong
    static let gray400 = Color(hex: "#A3A3A3") // text-tertiary (dark)
    static let gray500 = Color(hex: "#737373") // text-tertiary (light)
    static let gray600 = Color(hex: "#525252") // text-secondary
    static let gray700 = Color(hex: "#3D3D3D")
    static let gray800 = Color(hex: "#29241C") // ink-fill
    static let gray900 = Color(hex: "#191510") // ink text
    /// Dark-mode canvas — true black, not warm brown-black.
    static let gray950 = Color(hex: "#000000") // canvas (dark)
}

/// Cordovan ramp — kept for the darkest ink step (`primary900`) used as
/// `theme.primary` in light mode, and for leftover chart/tag call sites.
/// Mid-ramp steps are no longer card or page fills.
///
/// Mid-brown highlights come from `BrandColors.brand` via `theme.accent`,
/// not from this ramp and not from `theme.primary`.
struct PrimaryScale {
    static let primary50  = Color(hex: "#FAF5F2")
    static let primary100 = Color(hex: "#F2E9E3")
    static let primary200 = Color(hex: "#E6D8CE")
    static let primary300 = Color(hex: "#D4BFB1")
    static let primary400 = Color(hex: "#BB9E8C")
    static let primary500 = Color(hex: "#9D7F6C")
    static let primary600 = Color(hex: "#7E6252")
    static let primary700 = Color(hex: "#5F473A")
    static let primary800 = Color(hex: "#45322A")
    static let primary900 = Color(hex: "#2C1E19")
    static let primary950 = Color(hex: "#1B110E")
}

/// The brand hue — **highlights and force only**, never page/card/button fills.
/// Figma's `brand` is a more saturated family than any cordovan step
/// (`#A87549` vs cordovan-500 `#9D7F6C`).
struct BrandColors {
    /// Brand hue for highlights (sparkles, citations, focus, speaking).
    /// 3.96:1 on white — clears the 3:1 component threshold, but **not** 4.5:1
    /// for text. Wire through `theme.accent`, not `theme.primary`.
    static let brand     = Color(hex: "#A87549")
    static let brandDark = Color(hex: "#C89A6E")

    /// Use wherever brand carries white text, or where brand *is* text.
    /// `#A87549` gives only 3.96:1 against white — below AA. This is Figma's
    /// own `text-brand` / `button-brand-hover` at 5.75:1 on white.
    static let brandOnText = Color(hex: "#895C37")

    /// Sage-green secondary accent (Figma `highlight`).
    static let highlight     = Color(hex: "#4E6B5C")
    static let highlightDark = Color(hex: "#7E9B8B")

    /// Legacy cream / warm-dark surfaces. Cards now use `BaseColors.white` /
    /// `#111111`; these remain so leftover call sites do not break.
    static let surface     = Color(hex: "#FFFFFF")
    static let surfaceDark = Color(hex: "#111111")
}

/// Base colors - pure white and black
struct BaseColors {
    static let white = Color(hex: "#FFFFFF")
    static let offWhite = Color(hex: "#EFEFEF")
    static let black = Color(hex: "#000000")
}

// MARK: - Theme

struct Theme {
    // Base / sizing tokens
    let baseFontSize: CGFloat = 16
    struct Radius {
        let sm: CGFloat = 8
        let md: CGFloat = 12
        let button: CGFloat = 16  // Standard button corner radius
        let lg: CGFloat = 20    // For circular buttons (40pt diameter)
        let xl: CGFloat = 24    // For pills (48pt height)
        /// 32 — the chat composer, and the presentation corner radius the entry
        /// and summary sheets already pass literally. A fixed radius, not a
        /// capsule: the composer grows to five lines, and a capsule's radius
        /// grows with it, so the shape would change as you type.
        let xxl: CGFloat = 32
        let round: CGFloat = 999
    }
    let radius = Radius()

    struct Weights {
        let normal: Font.Weight = .regular
        let medium: Font.Weight = .medium
        let semibold: Font.Weight = .semibold
        let bold: Font.Weight = .bold
    }
    let weights = Weights()

    // Color palette (semantic)
    let background: Color
    let foreground: Color
    let card: Color
    let cardForeground: Color
    let cardBackground: Color  // Sunken card fill — one cool step under `card`
    let popover: Color
    let popoverForeground: Color
    let primary: Color
    let primaryForeground: Color
    let secondary: Color
    let secondaryForeground: Color
    let muted: Color
    let mutedForeground: Color
    let accent: Color
    let accentForeground: Color
    let destructive: Color
    let destructiveForeground: Color
    let border: Color
    let input: Color
    let inputBackground: Color
    let switchBackground: Color
    let ring: Color

    // Charts
    let chart1: Color
    let chart2: Color
    let chart3: Color
    let chart4: Color
    let chart5: Color

    // Follow-up card gradient
    let followUpGradientStart: Color
    let followUpGradientEnd: Color
    let followUpTagBackground: Color

    // FAB (Floating Action Button) gradient
    let fabGradientStart: Color
    let fabGradientEnd: Color

    // Header text gradient (for H1/H2 in Lora, H3 in Figtree)
    let headerGradientStart: Color
    let headerGradientEnd: Color

    // Background gradient (for hero sections or large cards)
    let backgroundGradientStart: Color
    let backgroundGradientEnd: Color
    var backgroundGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [backgroundGradientStart, backgroundGradientEnd]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Insights background gradient
    let insightsBackgroundStart: Color
    let insightsBackgroundEnd: Color
    var insightsBackground: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [insightsBackgroundStart, insightsBackgroundEnd]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Sidebar
    let sidebar: Color
    let sidebarForeground: Color
    let sidebarPrimary: Color
    let sidebarPrimaryForeground: Color
    let sidebarAccent: Color
    let sidebarAccentForeground: Color
    let sidebarBorder: Color
    let sidebarRing: Color

    // Overlay text (on former gradient cards; now matches foreground)
    let overlayText: Color
    let overlayTextSecondary: Color

    // Card-stroke color used on non-glass insight cards (decorative hairline).
    let glassBorder: Color

    // Emotion colors (for charts)
    let emotionJoy: Color
    let emotionSadness: Color
    let emotionAnger: Color
    let emotionFear: Color
    let emotionNeutral: Color

    // MARK: - Palettes

    static let light = Theme(
        background: BaseColors.white,
        foreground: BaseColors.black,
        card: BaseColors.white,
        cardForeground: BaseColors.black,
        cardBackground: GrayScale.gray100,
        popover: BaseColors.white,
        popoverForeground: BaseColors.black,
        // Darkest brown — filled buttons and block CTAs. Highlights use `accent`.
        primary: PrimaryScale.primary900,
        primaryForeground: BaseColors.white,
        secondary: GrayScale.gray100,
        secondaryForeground: BaseColors.black,
        muted: BaseColors.offWhite,
        mutedForeground: GrayScale.gray600,
        accent: BrandColors.brand,
        accentForeground: BaseColors.white,
        destructive: Color(hex: "#D4183D"),
        destructiveForeground: BaseColors.white,
        border: GrayScale.gray200,
        input: GrayScale.gray300,
        inputBackground: BaseColors.white,
        switchBackground: GrayScale.gray400,
        ring: BrandColors.brand,

        chart1: Color(hex: "#F54900"),
        chart2: Color(hex: "#009689"),
        chart3: Color(hex: "#104E64"),
        chart4: Color(hex: "#FFB900"),
        chart5: Color(hex: "#FE9A00"),

        followUpGradientStart: BaseColors.white,
        followUpGradientEnd: BaseColors.white,
        followUpTagBackground: GrayScale.gray100,

        fabGradientStart: PrimaryScale.primary900,
        fabGradientEnd: PrimaryScale.primary900,

        headerGradientStart: BaseColors.black,
        headerGradientEnd: BaseColors.black,

        backgroundGradientStart: BaseColors.white,
        backgroundGradientEnd: BaseColors.white,

        insightsBackgroundStart: BaseColors.white,
        insightsBackgroundEnd: BaseColors.white,

        sidebar: BaseColors.white,
        sidebarForeground: BaseColors.black,
        sidebarPrimary: PrimaryScale.primary900,
        sidebarPrimaryForeground: BaseColors.white,
        sidebarAccent: GrayScale.gray100,
        sidebarAccentForeground: BaseColors.black,
        sidebarBorder: GrayScale.gray200,
        sidebarRing: BrandColors.brand,

        overlayText: BaseColors.black,
        overlayTextSecondary: GrayScale.gray600,
        glassBorder: GrayScale.gray200,
        emotionJoy: Color(hex: "#7FE87D"),
        emotionSadness: Color(hex: "#5DD4E8"),
        emotionAnger: Color(hex: "#F19B8D"),
        emotionFear: Color(hex: "#B8B0E8"),
        emotionNeutral: Color(hex: "#A0D8F0")
    )

    static let dark = Theme(
        background: BaseColors.black,
        foreground: BaseColors.white,
        card: Color(hex: "#111111"),
        cardForeground: BaseColors.white,
        cardBackground: Color(hex: "#1A1A1A"),
        popover: Color(hex: "#111111"),
        popoverForeground: BaseColors.white,
        primary: BaseColors.white,
        primaryForeground: BaseColors.black,
        secondary: Color(hex: "#1A1A1A"),
        secondaryForeground: BaseColors.white,
        muted: Color(hex: "#1A1A1A"),
        mutedForeground: GrayScale.gray400,
        accent: BrandColors.brandDark,
        accentForeground: BaseColors.black,
        destructive: Color(hex: "#FF4D6A"),
        destructiveForeground: BaseColors.white,
        border: Color(hex: "#2A2A2A"),
        input: Color(hex: "#2A2A2A"),
        inputBackground: Color(hex: "#111111"),
        switchBackground: GrayScale.gray600,
        ring: BrandColors.brandDark,

        chart1: Color(hex: "#1447E6"),
        chart2: Color(hex: "#00BC7D"),
        chart3: Color(hex: "#FE9A00"),
        chart4: Color(hex: "#AD46FF"),
        chart5: Color(hex: "#FF2056"),

        followUpGradientStart: Color(hex: "#111111"),
        followUpGradientEnd: Color(hex: "#111111"),
        followUpTagBackground: Color(hex: "#1A1A1A"),

        fabGradientStart: BaseColors.white,
        fabGradientEnd: BaseColors.white,

        headerGradientStart: BaseColors.white,
        headerGradientEnd: BaseColors.white,

        backgroundGradientStart: Color(hex: "#111111"),
        backgroundGradientEnd: Color(hex: "#111111"),

        insightsBackgroundStart: BaseColors.black,
        insightsBackgroundEnd: BaseColors.black,

        sidebar: Color(hex: "#111111"),
        sidebarForeground: BaseColors.white,
        sidebarPrimary: BaseColors.white,
        sidebarPrimaryForeground: BaseColors.black,
        sidebarAccent: Color(hex: "#1A1A1A"),
        sidebarAccentForeground: BaseColors.white,
        sidebarBorder: Color(hex: "#2A2A2A"),
        sidebarRing: BrandColors.brandDark,

        overlayText: BaseColors.white,
        overlayTextSecondary: GrayScale.gray400,
        glassBorder: BaseColors.white.opacity(0.12),
        emotionJoy: Color(hex: "#8FFF8D"),
        emotionSadness: Color(hex: "#6DE4F8"),
        emotionAnger: Color(hex: "#FFAB9D"),
        emotionFear: Color(hex: "#C8C0F8"),
        emotionNeutral: Color(hex: "#B0E8FF")
    )
}

// MARK: - Environment convenience

struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

struct ThemeProvider: ViewModifier {
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var userPreference: AppThemePreference = .system
    @State private var themeObserver: NSObjectProtocol?

    func body(content: Content) -> some View {
        let effectiveTheme: Theme = {
            switch userPreference {
            case .system:
                return systemColorScheme == .dark ? .dark : .light
            case .light:
                return .light
            case .dark:
                return .dark
            }
        }()

        content
            .environment(\.theme, effectiveTheme)
            .preferredColorScheme(colorSchemeOverride)
            .onAppear {
                loadThemePreference()
                themeObserver = NotificationCenter.default.addObserver(
                    forName: .themePreferenceChanged,
                    object: nil,
                    queue: .main
                ) { _ in
                    loadThemePreference()
                }
            }
            .onDisappear {
                if let observer = themeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    themeObserver = nil
                }
            }
    }

    private var colorSchemeOverride: ColorScheme? {
        switch userPreference {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    private func loadThemePreference() {
        userPreference = PreferencesService.shared.themePreference
    }
}

extension View {
    func useTheme() -> some View { self.modifier(ThemeProvider()) }
}
