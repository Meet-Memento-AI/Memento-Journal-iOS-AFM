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

    /// Editor treatment is blur 100; list cards stay on the 12pt token.
    private var isEditorTreatment: Bool { defaults.blurStrength >= 50 }

    var body: some View {
        let params = resolved
        image
            .resizable()
            .scaledToFill()
            .scaleEffect(Self.fillScale(for: params.blurStrength, isEditor: isEditorTreatment))
            .blur(radius: params.blurStrength)
            .saturation(params.saturation)
            .overlay(JournalBackdropShader.scrimColor.opacity(params.scrimOpacity))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .modifier(ListBackdropRasterizeModifier(enabled: !isEditorTreatment))
    }

    /// Radius 100 needs more overflow than the card's 12pt treatment or
    /// the kernel hard-clips at the frame edge. List cards never take the
    /// 1.4 path — that scale exists only for the editor.
    static func fillScale(for blur: CGFloat, isEditor: Bool) -> CGFloat {
        if isEditor && blur >= 50 { return 1.4 }
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

/// Rasterizes the treated cover once so a scrolling LazyVStack does not
/// re-blur every frame. Off for the editor — blur 100 is a full-bleed
/// page fill, not a recycled row.
private struct ListBackdropRasterizeModifier: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.drawingGroup()
        } else {
            content
        }
    }
}
