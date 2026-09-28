//
//  JournalPhotoBackdrop.swift
//  withMemento
//
//  Treated-photo fill for JournalCard. Approximates Figma shader "Journal
//  backdrop" (786:2721): blur, saturation toward luma, and a WCAG scrim
//  when the cover is too bright for white type.
//

import SwiftUI
import UIKit

struct JournalPhotoBackdrop: View {
    let image: Image
    var sample: JournalBackdropSample? = nil
    var defaults: JournalBackdropParameters = JournalBackdropShader.designDefaults

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Rasterizes the treated cover once so a scrolling LazyVStack does not
    /// re-blur every frame at radius 100.
    var body: some View {
        let params = resolved
        let blur = min(params.blurStrength, JournalBackdropShader.maxBlur)
        image
            .resizable()
            .scaledToFill()
            .scaleEffect(Self.fillScale(for: blur))
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
            .drawingGroup()
    }

    /// Radius 100 needs extra overflow or the kernel hard-clips at the
    /// frame edge. `isEditor` is kept so older call sites still compile.
    static func fillScale(for blur: CGFloat, isEditor _: Bool = false) -> CGFloat {
        if blur >= 50 { return 1.4 }
        if blur > 0 { return 1.12 }
        return 1
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
