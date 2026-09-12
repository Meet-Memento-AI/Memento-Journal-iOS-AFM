//
//  JournalPhotoBackdrop.swift
//  MeetMemento
//
//  Treated-photo fill for JournalCard. Approximates Figma shader "Journal
//  backdrop" (786:2721): blur and saturation toward luma. Resting scrim is 0;
//  type on the card carries a light drop shadow instead.
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
        let blur = min(params.blurStrength, JournalBackdropShader.maxBlur)
        image
            .resizable()
            .scaledToFill()
            .scaleEffect(fillScale(for: blur))
            .blur(radius: blur)
            .brightness(blur > 0 ? JournalBackdropShader.treatedBrightness : 0)
            .saturation(params.saturation)
            .overlay {
                if params.scrimOpacity > 0.001 {
                    JournalBackdropShader.scrimColor.opacity(params.scrimOpacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Overflow so the clamped kernel does not hard-clip at the frame edge.
    private func fillScale(for blur: CGFloat) -> CGFloat {
        blur > 0 ? 1.12 : 1
    }

    private var resolved: JournalBackdropParameters {
        JournalBackdropContrast.resolved(
            sample: sample,
            base: defaults,
            increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled,
            reduceTransparency: reduceTransparency
        )
    }
}
