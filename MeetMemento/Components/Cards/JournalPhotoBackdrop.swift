//
//  JournalPhotoBackdrop.swift
//  MeetMemento
//
//  Shared treated-photo fill for JournalCard and the photo-backed editor.
//  Approximates Figma shader "Journal backdrop" (786:2721 / 818:4087):
//  blur, saturation toward luma, mix toward a dark scrim.
//

import SwiftUI
import UIKit

struct JournalPhotoBackdrop: View {
    let image: Image
    var sample: JournalBackdropSample? = nil
    var defaults: JournalBackdropParameters = JournalBackdropShader.designDefaults

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let params = resolved
        image
            .resizable()
            .scaledToFill()
            .scaleEffect(fillScale(for: params.blurStrength))
            .blur(radius: params.blurStrength)
            .saturation(params.saturation)
            .overlay(JournalBackdropShader.scrimColor.opacity(params.scrimOpacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Radius 100 needs more overflow than the card's 12pt treatment or
    /// the kernel hard-clips at the frame edge.
    private func fillScale(for blur: CGFloat) -> CGFloat {
        if blur >= 50 { return 1.4 }
        if blur > 0 { return 1.12 }
        return 1
    }

    private var resolved: JournalBackdropParameters {
        let increaseContrast = UIAccessibility.isDarkerSystemColorsEnabled
        if let sample {
            return JournalBackdropContrast.parameters(
                sample: sample,
                base: defaults,
                increaseContrast: increaseContrast,
                reduceTransparency: reduceTransparency
            )
        }
        var params = defaults
        if reduceTransparency { params.blurStrength = 0 }
        if increaseContrast {
            params.scrimOpacity = max(
                params.scrimOpacity,
                JournalBackdropShader.increaseContrastFloor
            )
        }
        return params
    }
}
