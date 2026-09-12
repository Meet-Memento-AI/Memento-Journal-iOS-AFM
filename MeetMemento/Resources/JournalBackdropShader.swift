//
//  JournalBackdropShader.swift
//  MeetMemento
//
//  Tokenized Figma shader "Journal backdrop" (node 786:2721). The WebGPU
//  runtime cannot run on iOS; these are the three operations that shader
//  applies (separable Gaussian, saturation toward luma, mix toward a dark
//  scrim), with the *applied* instance values as defaults.
//

import SwiftUI

/// Average sRGB of a cover photo, sampled once when the thumbnail decrypts.
struct JournalBackdropSample: Equatable, Sendable, Codable {
    let red: Double
    let green: Double
    let blue: Double
}

/// Resolved blur / saturation / scrim to apply on a photo card.
struct JournalBackdropParameters: Equatable, Sendable {
    var blurStrength: CGFloat
    var scrimOpacity: Double
    var saturation: Double
}

/// A glass tint derived from a cover photo: the wash colour, and how much of
/// it to lay over the surface.
///
/// Held as components rather than a `Color` so the contrast search can walk
/// the opacity without a colour-space round trip per step — see
/// `JournalBackdropContrast.chromeTint`.
struct JournalChromeTint: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }

    /// Same wash, with opacity scaled. AddEntry photo chrome keeps ~30% of
    /// the solved wash so the cover shows through the pills.
    func color(opacityKeep: Double) -> Color {
        Color(red: red, green: green, blue: blue).opacity(opacity * opacityKeep)
    }
}

extension Glass {
    /// Hair of white on `.clear`. Enough to read as frost, not a plate.
    static let nativeFrostOpacity: Double = 0.08

    /// Native Liquid Glass for floating chrome: `.clear` so it does not
    /// paint a white disc, plus `nativeFrostOpacity` so it still frosts.
    static func native(interactive: Bool = true) -> Glass {
        let glass = Glass.clear.tint(Color.white.opacity(nativeFrostOpacity))
        return interactive ? glass.interactive() : glass
    }

    /// `.regular` glass, optionally washed with a backdrop-derived tint.
    ///
    /// Nil tint uses `native` (clear + a hair of frost). A tint is a
    /// prominence signal (Welcome Get Started, labeled FAB).
    static func chrome(tint: Color?, interactive: Bool = true) -> Glass {
        if let tint {
            let glass = Glass.regular.tint(tint)
            return interactive ? glass.interactive() : glass
        }
        return native(interactive: interactive)
    }

    /// Scheme-flipped frost for a primary action (Capture on the plain
    /// editor). Density sits in the Welcome Get Started band so the tint
    /// reads *through* the material instead of covering it. Ink is the
    /// inverse of the wash: white in light, black in dark.
    static func prominentFrost(
        colorScheme: ColorScheme,
        interactive: Bool = true,
        increaseContrast: Bool = false,
        reduceTransparency: Bool = false
    ) -> Glass {
        let opacity = JournalBackdropShader.prominentFrostOpacity(
            increaseContrast: increaseContrast,
            reduceTransparency: reduceTransparency
        )
        let wash = (colorScheme == .dark ? Color.white : Color.black)
            .opacity(opacity)
        return chrome(tint: wash, interactive: interactive)
    }
}

enum JournalBackdropShader {
    /// Soft treatment for journal covers. Cards at 19.2pt, editor at 38.4pt
    /// (double the prior 9.6 / 19.2) so the stylish blur still reads.
    static let blurStrength: CGFloat = 19.2
    /// Resting scrim. 0 — type uses a drop shadow instead of a dark plate.
    static let scrimOpacity: Double = 0
    /// Keep the cover's own colour. Pulling toward luma (the old 0.89–0.92)
    /// greys the photo and reads as another darkening pass.
    static let saturation: Double = 1.0
    /// Shader `scrimColor` `vec3f(0.039)`.
    static let scrimColor = Color(red: 0.039, green: 0.039, blue: 0.039)
    static let scrimRed = 0.039
    static let scrimGreen = 0.039
    static let scrimBlue = 0.039
    /// WCAG AA for normal text. Title is 20pt (large-text 3:1 would pass);
    /// white-on-photo still aims at 4.5.
    static let minimumContrast: Double = 4.5
    static let maxBlur: CGFloat = 40
    /// Gaussian blur pulls highlights toward midtones. A small lift after
    /// the blur keeps the cover from reading as a dark wash.
    static let treatedBrightness: Double = 0.08
    /// Increase Contrast accessibility floor for scrim. Resting product
    /// chrome uses 0; this only applies when the user asks for more contrast.
    static let increaseContrastFloor: Double = 0.16

    // MARK: Chrome tint

    /// Resting wash for glass floating on a cover, used whenever the backdrop
    /// already gives white glyphs their contrast. Aesthetic, not corrective.
    static let chromeTintFloor: Double = 0.08
    /// Ceiling. Past this the surface stops refracting and reads as a flat
    /// panel, which is the one thing a tint must never turn glass into.
    static let chromeTintCeiling: Double = 0.45
    /// How much of the cover's own chroma survives into the wash. A cover
    /// average laid on at full chroma colours the chrome; pulled toward its
    /// luma it seats the chrome in the photo instead of painting a disc.
    static let chromeTintChroma: Double = 0.55
    /// How far the wash sits toward the scrim. Darkening is the only lever
    /// here, the same one `scrimOpacity` is for the backdrop: white is the
    /// only ink the editor puts on a photo. Kept shallow so frost picks up
    /// the cover rather than sitting as a charcoal pill on it.
    static let chromeTintDepth: Double = 0.4
    /// Resting prominence-frost density (Capture). Welcome Get Started is
    /// 0.24; this sits a step denser so the CTA still reads against untinted
    /// sibling chrome, without becoming a slab (the old 0.9).
    static let prominentFrostFloor: Double = 0.28
    /// Increase Contrast bump for prominence frost. Still under
    /// `chromeTintCeiling`, so the surface stays glass.
    static let prominentFrostIncreaseContrast: Double = 0.40
    /// Increase Contrast target for white on tinted chrome (WCAG AAA).
    static let chromeIncreasedContrast: Double = 7.0
    /// Reduce Transparency cannot remove the glass, so it thickens the wash.
    static let chromeReduceTransparencyFloor: Double = 0.32
    /// AddEntry photo chrome applies this fraction of the solved wash so
    /// the cover shows through. `0.3` drops about 70% of the tint opacity.
    static let photoChromeTintKeep: Double = 0.3

    /// Prominence-frost opacity after accessibility floors. Not a WCAG
    /// search against the canvas: even `chromeTintCeiling` cannot put white
    /// ink at 4.5:1 on a white plate as a flat mix, and chasing it would
    /// turn Capture back into a panel. System frost plus vibrancy is the
    /// remaining contrast, same contract as Welcome Get Started.
    static func prominentFrostOpacity(
        increaseContrast: Bool,
        reduceTransparency: Bool
    ) -> Double {
        var opacity = prominentFrostFloor
        if reduceTransparency {
            opacity = max(opacity, chromeReduceTransparencyFloor)
        }
        if increaseContrast {
            opacity = max(opacity, prominentFrostIncreaseContrast)
        }
        return min(opacity, chromeTintCeiling)
    }

    static let designDefaults = JournalBackdropParameters(
        blurStrength: blurStrength,
        scrimOpacity: scrimOpacity,
        saturation: saturation
    )

    /// Editor cover — double the prior 19.2pt treatment.
    static let editorDefaults = JournalBackdropParameters(
        blurStrength: 38.4,
        scrimOpacity: 0,
        saturation: 1.0
    )
}
