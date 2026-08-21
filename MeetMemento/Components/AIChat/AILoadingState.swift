//
//  AILoadingState.swift
//  MeetMemento
//
//  Created by Sebastian Mendo on 1/15/26.
//

import SwiftUI

struct AILoadingState: View {
    var phrase: String = LoadingStatus.fallback
    @Environment(\.theme) private var theme
    @State private var isAnimating = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Icon on the left
            Image("Icon-Underline")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            // Shimmer text
            ZStack {
                // 1. Base Text (Static Gray - Dimmed)
                loadingText
                    .foregroundStyle(theme.mutedForeground.opacity(0.3))

                // 2. Wave Text (Shimmer - Full Color)
                loadingText
                    .foregroundStyle(theme.mutedForeground)
                    .mask(
                        GeometryReader { geometry in
                            LinearGradient(
                                colors: [.clear, .white, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            // Frame width exactly matches text width to prevent excessive "off-screen" travel time
                            .frame(width: geometry.size.width)
                            // Start: View displaced fully left (-width) -> Center of gradient (white) is at -0.5*width
                            // End: View displaced fully right (+width) -> Center of gradient (white) is at 1.5*width
                            // Result: The white center swipes perfectly from left to right with minimal delay
                            .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
                        }
                    )
            }
        }
        .accessibilityLabel(phrase)
        .accessibilityAddTraits(.updatesFrequently)
        .onAppear {
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
        }
    }
    
    private var loadingText: some View {
        Text(phrase)
            .typographyLoadingHeading()
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemBackground).ignoresSafeArea()
        AILoadingState()
            .useTheme()
            .useTypography()
    }
}
