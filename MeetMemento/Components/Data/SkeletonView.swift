import SwiftUI

public struct SkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Double = 0.0

    public init(width: CGFloat? = nil, height: CGFloat, cornerRadius: CGFloat = 8) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        ZStack {
            // Base layer
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.05))

            // Breathing wave layer (static when reduce motion enabled)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                .opacity(reduceMotion ? 0.5 : (0.3 + 0.7 * (0.5 + 0.5 * sin(phase))))
        }
        .frame(width: width, height: height)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                phase = .pi
            }
        }
        .onDisappear {
            // Reset phase to stop animation calculations
            phase = 0
        }
    }
}

public extension View {
    @ViewBuilder
    func skeleton(if condition: Bool, width: CGFloat? = nil, height: CGFloat? = nil, cornerRadius: CGFloat = 8) -> some View {
        if condition {
            SkeletonView(width: width, height: height ?? 20, cornerRadius: cornerRadius)
        } else {
            self
        }
    }
}
