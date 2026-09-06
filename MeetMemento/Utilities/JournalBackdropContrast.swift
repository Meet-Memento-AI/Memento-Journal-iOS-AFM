//
//  JournalBackdropContrast.swift
//  MeetMemento
//
//  Adapts JournalBackdropShader tokens so white title type on a photo
//  card or editor meets WCAG AA (4.5:1). Scrim is the contrast lever; blur
//  is a secondary bump; saturation stays at the supplied base token.
//

import CoreGraphics
import UIKit

enum JournalBackdropContrast {
    /// Samples a cover photo down to 16×16 and averages sRGB.
    static func sample(image: UIImage) -> JournalBackdropSample {
        averageSRGB(of: image)
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
    static func parameters(
        srgb: (r: Double, g: Double, b: Double),
        base: JournalBackdropParameters = JournalBackdropShader.designDefaults,
        increaseContrast: Bool = false,
        reduceTransparency: Bool = false
    ) -> JournalBackdropParameters {
        let sat = base.saturation
        var scrim = max(
            base.scrimOpacity,
            increaseContrast ? JournalBackdropShader.increaseContrastFloor : 0
        )
        var blur = reduceTransparency ? 0 : base.blurStrength

        if contrast(srgb: srgb, saturation: sat, scrimOpacity: scrim) >= JournalBackdropShader.minimumContrast {
            return JournalBackdropParameters(blurStrength: blur, scrimOpacity: scrim, saturation: sat)
        }

        var step = 0.02
        while scrim < 1.0 - 1e-6 {
            scrim = min(1.0, scrim + step)
            if contrast(srgb: srgb, saturation: sat, scrimOpacity: scrim) >= JournalBackdropShader.minimumContrast {
                return JournalBackdropParameters(blurStrength: blur, scrimOpacity: scrim, saturation: sat)
            }
        }

        if !reduceTransparency {
            blur = max(blur, JournalBackdropShader.maxBlur)
        }
        return JournalBackdropParameters(blurStrength: blur, scrimOpacity: 1.0, saturation: sat)
    }

    /// White-on-composite contrast after the shader's sat + scrim mix.
    static func contrast(
        srgb: (r: Double, g: Double, b: Double),
        saturation: Double,
        scrimOpacity: Double
    ) -> Double {
        let lum = rec709Luma(srgb.r, srgb.g, srgb.b)
        let saturatedR = mix(lum, srgb.r, saturation)
        let saturatedG = mix(lum, srgb.g, saturation)
        let saturatedB = mix(lum, srgb.b, saturation)
        let resultR = mix(saturatedR, JournalBackdropShader.scrimRed, scrimOpacity)
        let resultG = mix(saturatedG, JournalBackdropShader.scrimGreen, scrimOpacity)
        let resultB = mix(saturatedB, JournalBackdropShader.scrimBlue, scrimOpacity)
        let bg = relativeLuminance(resultR, resultG, resultB)
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
