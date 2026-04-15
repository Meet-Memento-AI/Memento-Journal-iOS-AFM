//
//  ProgressiveBlurHeaderWrapper.swift
//  MeetMemento
//
//  A theme-aware wrapper around ProgressiveBlurHeader for consistent
//  progressive blur effects across scrollable views with floating headers.
//
//  Blur Coverage: The total blur height = headerHeight + fadeExtension.
//  Keep this between 64-80px total for optimal visual effect.
//

import SwiftUI
import ProgressiveBlurHeader

struct ProgressiveBlurHeaderWrapper<Content: View>: View {
    let headerHeight: CGFloat
    let fadeExtension: CGFloat
    let maxBlurRadius: CGFloat
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    /// Creates a progressive blur header wrapper.
    /// - Parameters:
    ///   - headerHeight: Height of the header area to blur (typically 44-52px)
    ///   - fadeExtension: Additional blur fade below header (typically 16-24px)
    ///   - maxBlurRadius: Blur intensity (default 5, subtle)
    ///   - content: The scrollable content
    init(
        headerHeight: CGFloat = 52,
        fadeExtension: CGFloat = 20,
        maxBlurRadius: CGFloat = 5,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.headerHeight = headerHeight
        self.fadeExtension = fadeExtension
        self.maxBlurRadius = maxBlurRadius
        self.content = content
    }

    var body: some View {
        StickyBlurHeader(
            maxBlurRadius: maxBlurRadius,
            fadeExtension: fadeExtension,
            tintOpacityTop: colorScheme == .dark ? 0.7 : 0.6,
            tintOpacityMiddle: colorScheme == .dark ? 0.4 : 0.3
        ) {
            // Invisible header spacer - defines blur origin height
            Color.clear.frame(height: headerHeight)
        } content: {
            content()
        }
    }
}

#Preview("Light Mode - 72px blur") {
    // Total blur: 52 (header) + 20 (fade) = 72px
    ProgressiveBlurHeaderWrapper(
        headerHeight: 52,
        fadeExtension: 20,
        maxBlurRadius: 5
    ) {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<20, id: \.self) { i in
                    Text("Item \(i)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding()
            .padding(.top, 52) // Content inset to clear header
        }
    }
    .useTheme()
}

#Preview("Dark Mode - 72px blur") {
    ProgressiveBlurHeaderWrapper(
        headerHeight: 52,
        fadeExtension: 20,
        maxBlurRadius: 5
    ) {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(0..<20, id: \.self) { i in
                    Text("Item \(i)")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding()
            .padding(.top, 52)
        }
    }
    .useTheme()
    .preferredColorScheme(.dark)
}
