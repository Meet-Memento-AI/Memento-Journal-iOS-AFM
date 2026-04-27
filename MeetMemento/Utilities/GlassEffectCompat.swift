import SwiftUI

/// Lightweight compatibility wrapper for glass-like backgrounds on SDKs
/// that do not expose SwiftUI's native glassEffect APIs.
enum MementoGlassStyle {
    case regular

    func interactive() -> MementoGlassStyle {
        self
    }
}

extension View {
    @ViewBuilder
    func mementoGlassEffect(_ style: MementoGlassStyle, in shape: some Shape) -> some View {
        switch style {
        case .regular:
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @ViewBuilder
    func mementoGlassEffect(in shape: some Shape) -> some View {
        self.background(.ultraThinMaterial, in: shape)
    }
}
