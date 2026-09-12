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

    /// Editor treatment is blur 100; list cards stay on the 12pt token.
    private var isEditorTreatment: Bool { defaults.blurStrength >= 50 }

    var body: some View {
        let params = resolved
        // Cards clamp the kernel; the editor keeps blur 100 so fillScale
        // can take the 1.4 overflow path.
        let blur = isEditorTreatment
            ? params.blurStrength
            : min(params.blurStrength, JournalBackdropShader.maxBlur)
        image
            .resizable()
            .scaledToFill()
            .scaleEffect(Self.fillScale(for: blur, isEditor: isEditorTreatment))
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
        JournalBackdropContrast.resolved(
            sample: sample,
            base: defaults,
            increaseContrast: UIAccessibility.isDarkerSystemColorsEnabled,
            reduceTransparency: reduceTransparency
        )
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
