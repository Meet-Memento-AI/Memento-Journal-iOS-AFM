import SwiftUI

/// Compatibility wrapper for glass-like backgrounds.
/// Branches to SwiftUI's native Liquid Glass API on iOS 26+, and falls back
/// to a material-based approximation (honoring tint/interactive as best it
/// can) on older OS versions or SDKs that don't expose the native API.
struct MementoGlassStyle {
    static let regular = MementoGlassStyle()

    fileprivate var tintColor: Color?
    fileprivate var isInteractive: Bool = false

    func tint(_ color: Color) -> MementoGlassStyle {
        var copy = self
        copy.tintColor = color
        return copy
    }

    func interactive() -> MementoGlassStyle {
        var copy = self
        copy.isInteractive = true
        return copy
    }
}

extension View {
    @ViewBuilder
    func mementoGlassEffect(_ style: MementoGlassStyle, in shape: some InsettableShape) -> some View {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            self.glassEffect(style.nativeGlass, in: shape)
        } else {
            self.mementoGlassEffectFallback(style, in: shape)
        }
        #else
        self.mementoGlassEffectFallback(style, in: shape)
        #endif
    }

    @ViewBuilder
    func mementoGlassEffect(in shape: some InsettableShape) -> some View {
        mementoGlassEffect(.regular, in: shape)
    }

    @ViewBuilder
    private func mementoGlassEffectFallback(_ style: MementoGlassStyle, in shape: some InsettableShape) -> some View {
        // Material-only approximation: real Liquid Glass isn't available, so
        // layer the requested tint (if any) under a thin material to at least
        // suggest the same color without faking specular/refraction effects.
        // Border matches Theme.glassBorder, which is the same constant
        // (white 20% opacity) in both light and dark themes.
        self
            .background(style.tintColor?.opacity(0.18) ?? Color.clear, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private extension MementoGlassStyle {
    var nativeGlass: Glass {
        var glass = Glass.regular
        if let tintColor {
            glass = glass.tint(tintColor)
        }
        if isInteractive {
            glass = glass.interactive()
        }
        return glass
    }
}
#endif
