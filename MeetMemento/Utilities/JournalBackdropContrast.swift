//
//  JournalBackdropContrast.swift
//  MeetMemento
//
//  Adapts JournalBackdropShader tokens. Dark covers keep a 0 scrim so the
//  photo reads through. Bright covers get the lightest dark overlay that
//  puts white type at WCAG AA (4.5:1). Increase Contrast raises a floor;
//  Reduce Transparency still zeroes blur. A drop shadow on the glyphs is
//  extra insurance, not a substitute for the overlay.
//

import CoreGraphics
import UIKit

enum JournalBackdropContrast {
    /// Samples a cover photo down to 16×16 and averages sRGB.
    static func sample(image: UIImage) -> JournalBackdropSample {
        averageSRGB(of: image)
    }

    /// What a cover actually renders with. Card and editor share this path
    /// so a bright sky gets the same veil in the list and in the editor.
    static func resolved(
        sample: JournalBackdropSample?,
        base: JournalBackdropParameters,
        increaseContrast: Bool,
        reduceTransparency: Bool
    ) -> JournalBackdropParameters {
        if let sample {
            return parameters(
                sample: sample,
                base: base,
                increaseContrast: increaseContrast,
                reduceTransparency: reduceTransparency
            )
        }
        var params = base
        if reduceTransparency { params.blurStrength = 0 }
        if increaseContrast {
            params.scrimOpacity = max(
                params.scrimOpacity,
                JournalBackdropShader.increaseContrastFloor
            )
        }
        return params
    }

    static func parameters(
        for image: UIImage,
        base: JournalBackdropParameters = JournalBackdropShader.designDefaults,
        increaseContrast: Bool = false,
        reduceTransparency: Bool = false
    ) -> JournalBackdropParameters {
        parameters(
            sample: sample(image: image),
            base: base,
            increaseContrast: increaseContrast,
            reduceTransparency: reduceTransparency
        )
    }

    static func parameters(
        sample: JournalBackdropSample,
        base: JournalBackdropParameters = JournalBackdropShader.designDefaults,
        increaseContrast: Bool = false,
        reduceTransparency: Bool = false
    ) -> JournalBackdropParameters {
        parameters(
            srgb: (sample.red, sample.green, sample.blue),
            base: base,
            increaseContrast: increaseContrast,
            reduceTransparency: reduceTransparency
        )
    }

    /// Pure RGB path for tests (values in 0...1, display-referred sRGB).
    ///
    /// Scrim search is one-way: it only ever raises. Dark covers stay at the
    /// token (0). Bright covers search up until white-on-composite hits
    /// `minimumContrast`, then stop — the smallest veil that still passes.
    /// A ceiling keeps a white sky from becoming a charcoal plate.
    static func parameters(
        srgb: (r: Double, g: Double, b: Double),
        base: JournalBackdropParameters = JournalBackdropShader.designDefaults,
        increaseContrast: Bool = false,
        reduceTransparency: Bool = false
    ) -> JournalBackdropParameters {
        let sat = base.saturation
        let blur = reduceTransparency ? 0 : base.blurStrength
        let brightness = blur > 0 ? JournalBackdropShader.treatedBrightness : 0
        var floor = base.scrimOpacity
        if increaseContrast {
            floor = max(floor, JournalBackdropShader.increaseContrastFloor)
        }
        let scrim = scrimOpacity(
            srgb: srgb,
            saturation: sat,
            brightness: brightness,
            floor: floor,
            ceiling: JournalBackdropShader.scrimCeiling,
            target: JournalBackdropShader.minimumContrast
        )
        return JournalBackdropParameters(
            blurStrength: blur,
            scrimOpacity: scrim,
            saturation: sat
        )
    }

    /// Smallest dark overlay that puts white ink at `target` on this cover.
    /// Binary search so the veil is no heavier than WCAG requires.
    static func scrimOpacity(
        srgb: (r: Double, g: Double, b: Double),
        saturation: Double,
        brightness: Double,
        floor: Double,
        ceiling: Double,
        target: Double
    ) -> Double {
        let loBound = min(max(floor, 0), ceiling)
        let hiBound = max(ceiling, loBound)
        func ratio(_ scrim: Double) -> Double {
            contrast(
                srgb: srgb,
                saturation: saturation,
                scrimOpacity: scrim,
                brightness: brightness
            )
        }
        if ratio(loBound) >= target { return loBound }
        if ratio(hiBound) < target { return hiBound }
        var lo = loBound
        var hi = hiBound
        for _ in 0..<16 {
            let mid = (lo + hi) / 2
            if ratio(mid) >= target {
                hi = mid
            } else {
                lo = mid
            }
        }
        return hi
    }

    /// The colour a cover actually presents after brightness, saturation and
    /// scrim. Matches the card/editor stack: lift, then sat, then the overlay.
    /// Shared by the WCAG search and the chrome tint so the two cannot
    /// disagree about what is behind the glass.
    static func composite(
        srgb: (r: Double, g: Double, b: Double),
        saturation: Double,
        scrimOpacity: Double,
        brightness: Double = 0
    ) -> (r: Double, g: Double, b: Double) {
        let lifted = (
            r: min(1, max(0, srgb.r + brightness)),
            g: min(1, max(0, srgb.g + brightness)),
            b: min(1, max(0, srgb.b + brightness))
        )
        let lum = rec709Luma(lifted.r, lifted.g, lifted.b)
        let saturatedR = mix(lum, lifted.r, saturation)
        let saturatedG = mix(lum, lifted.g, saturation)
        let saturatedB = mix(lum, lifted.b, saturation)
        return (
            mix(saturatedR, JournalBackdropShader.scrimRed, scrimOpacity),
            mix(saturatedG, JournalBackdropShader.scrimGreen, scrimOpacity),
            mix(saturatedB, JournalBackdropShader.scrimBlue, scrimOpacity)
        )
    }

    /// White-on-composite contrast after the shader's lift + sat + scrim mix.
    static func contrast(
        srgb: (r: Double, g: Double, b: Double),
        saturation: Double,
        scrimOpacity: Double,
        brightness: Double = 0
    ) -> Double {
        let result = composite(
            srgb: srgb,
            saturation: saturation,
            scrimOpacity: scrimOpacity,
            brightness: brightness
        )
        let bg = relativeLuminance(result.r, result.g, result.b)
        return contrastRatio(foreground: 1.0, background: bg)
    }

    // MARK: - Chrome glyph ink

    /// Black on Liquid Glass is the default. White only when a cover is so
    /// dark that black glyphs on the frosted capsule fall below
    /// `chromeGlyphBlackFloor`. No sample (plain editor) always prefers black.
    static func prefersWhiteChromeGlyphs(
        sample: JournalBackdropSample?,
        params: JournalBackdropParameters,
        scrimFactor: Double
    ) -> Bool {
        guard let sample else { return false }
        let factor = min(max(scrimFactor, 0), 1)
        let brightness = (params.blurStrength > 0 && factor > 0)
            ? JournalBackdropShader.treatedBrightness * factor
            : 0
        let backdrop = composite(
            srgb: (sample.red, sample.green, sample.blue),
            saturation: params.saturation,
            scrimOpacity: params.scrimOpacity * factor,
            brightness: brightness
        )
        let frost = JournalBackdropShader.glassFrostOpacity
        let surface = relativeLuminance(
            mix(backdrop.r, 1, frost),
            mix(backdrop.g, 1, frost),
            mix(backdrop.b, 1, frost)
        )
        let blackContrast = contrastRatio(foreground: 0, background: surface)
        if blackContrast >= JournalBackdropShader.chromeGlyphBlackFloor {
            return false
        }
        let whiteContrast = contrastRatio(foreground: 1, background: surface)
        return whiteContrast > blackContrast
    }

    // MARK: - Chrome tint

    /// Glass tint for chrome floating on a cover photo.
    ///
    /// Beyond seating the chrome in the photo, the tint has one job: white is
    /// the only ink the editor puts on a cover, so the wash has to keep it
    /// legible against whatever the glass is refracting. `scrimFactor` says
    /// how much of the backdrop's scrim is currently down — 1 on the treated
    /// backdrop, 0 on a revealed memory, where the raw cover sits directly
    /// behind the pills and a bright sky would otherwise swallow the glyphs.
    ///
    /// Only ever darkens, for the same reason `parameters(srgb:…)` only ever
    /// raises the scrim: one lever, moving one way, is a search that always
    /// terminates somewhere predictable.
    static func chromeTint(
        sample: JournalBackdropSample?,
        params: JournalBackdropParameters,
        scrimFactor: Double,
        increaseContrast: Bool,
        reduceTransparency: Bool
    ) -> JournalChromeTint {
        let backdrop = chromeBackdrop(
            sample: sample,
            params: params,
            scrimFactor: scrimFactor
        )

        // The wash carries the cover's cast, muted toward luma, then a
        // shallow mix toward the scrim so raising opacity darkens the frost
        // without turning it into a charcoal disc.
        let chroma = JournalBackdropShader.chromeTintChroma
        let depth = JournalBackdropShader.chromeTintDepth
        let lum = rec709Luma(backdrop.r, backdrop.g, backdrop.b)
        let wash = (
            r: mix(mix(lum, backdrop.r, chroma), JournalBackdropShader.scrimRed, depth),
            g: mix(mix(lum, backdrop.g, chroma), JournalBackdropShader.scrimGreen, depth),
            b: mix(mix(lum, backdrop.b, chroma), JournalBackdropShader.scrimBlue, depth)
        )

        let target = increaseContrast
            ? JournalBackdropShader.chromeIncreasedContrast
            : JournalBackdropShader.minimumContrast
        let floor = reduceTransparency
            ? JournalBackdropShader.chromeReduceTransparencyFloor
            : JournalBackdropShader.chromeTintFloor
        let ceiling = JournalBackdropShader.chromeTintCeiling

        func tint(_ opacity: Double) -> JournalChromeTint {
            JournalChromeTint(red: wash.r, green: wash.g, blue: wash.b, opacity: opacity)
        }

        var opacity = min(floor, ceiling)
        if chromeContrast(tint: tint(opacity), over: backdrop) >= target {
            return tint(opacity)
        }

        let step = 0.02
        while opacity < ceiling - 1e-6 {
            opacity = min(ceiling, opacity + step)
            if chromeContrast(tint: tint(opacity), over: backdrop) >= target {
                return tint(opacity)
            }
        }
        // Capped rather than solved: past the ceiling this stops being glass.
        return tint(ceiling)
    }

    /// What sits behind the chrome at a given point in the reveal.
    /// `scrimFactor` 1 is the treated backdrop, 0 the bare cover.
    static func chromeBackdrop(
        sample: JournalBackdropSample?,
        params: JournalBackdropParameters,
        scrimFactor: Double
    ) -> (r: Double, g: Double, b: Double) {
        let srgb = sample.map { ($0.red, $0.green, $0.blue) } ?? (0.5, 0.5, 0.5)
        return composite(
            srgb: srgb,
            saturation: params.saturation,
            scrimOpacity: params.scrimOpacity * min(max(scrimFactor, 0), 1)
        )
    }

    /// White-on-glass contrast once `tint` is laid over `backdrop`. The
    /// search above is defined in terms of this, so a test asserting it is
    /// asserting the guarantee itself rather than a re-derivation of it.
    static func chromeContrast(
        tint: JournalChromeTint,
        over backdrop: (r: Double, g: Double, b: Double)
    ) -> Double {
        let bg = relativeLuminance(
            mix(backdrop.r, tint.red, tint.opacity),
            mix(backdrop.g, tint.green, tint.opacity),
            mix(backdrop.b, tint.blue, tint.opacity)
        )
        return contrastRatio(foreground: 1.0, background: bg)
    }

    static func contrastRatio(foreground: Double, background: Double) -> Double {
        let lighter = max(foreground, background)
        let darker = min(foreground, background)
        return (lighter + 0.05) / (darker + 0.05)
    }

    // MARK: - Sampling

    private static func averageSRGB(of image: UIImage) -> JournalBackdropSample {
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cg = image.cgImage else {
            return JournalBackdropSample(red: 0.5, green: 0.5, blue: 0.5)
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3])
            if a < 2 { continue }
            r += Double(pixels[i]) / 255
            g += Double(pixels[i + 1]) / 255
            b += Double(pixels[i + 2]) / 255
            n += 1
        }
        guard n > 0 else {
            return JournalBackdropSample(red: 0.5, green: 0.5, blue: 0.5)
        }
        return JournalBackdropSample(red: r / n, green: g / n, blue: b / n)
    }

    /// Shader luma weights (same as the WGSL `dot(col.rgb, vec3f(0.2126, …))`).
    private static func rec709Luma(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func relativeLuminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private static func linearize(_ c: Double) -> Double {
        let x = min(max(c, 0), 1)
        if x <= 0.04045 { return x / 12.92 }
        return pow((x + 0.055) / 1.055, 2.4)
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
