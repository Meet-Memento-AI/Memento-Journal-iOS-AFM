//
//  JournalBackdropRenderer.swift
//  MeetMemento
//
//  Bakes the editor's "Journal backdrop" treatment (blur + saturation) into
//  one small bitmap, once, off the main thread.
//
//  Why not a live `.blur`: the editor cover is a screen-sized layer (often
//  ~3× screen width for a landscape photo under `scaledToFill`) with four
//  Liquid Glass surfaces on top. A CoreAnimation blur on that layer is
//  re-evaluated every frame of the zoom transition and again per glass
//  sampler. That is fine on a Mac GPU in the Simulator and stalls the
//  editor on device. A static image costs nothing per frame; the reveal is
//  an opacity crossfade instead of an animated filter radius.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum JournalBackdropRenderer {
    /// Longest edge, in pixels, of the rendered bitmap. The result is heavily
    /// blurred, so upscaling to full-bleed shows no loss.
    static let maxPixelSize: CGFloat = 512

    /// Fallback display size when no window scene is available (iPhone 17).
    private static let fallbackDisplaySize = CGSize(width: 402, height: 874)

    /// Shared context: creating one is the expensive part of CoreImage.
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .priorityRequestLow: false
    ])

    /// Points → pixels reference for the blur radius. Read on the main
    /// thread and passed in so the render itself can run detached.
    @MainActor
    static func currentDisplaySize() -> CGSize {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let size = scene?.screen.bounds.size ?? fallbackDisplaySize
        return size.width > 0 && size.height > 0 ? size : fallbackDisplaySize
    }

    /// Blur + saturation from `params`, sized for `scaledToFill` in
    /// `displaySize`. The scrim is not baked in — it stays a cheap `Color`
    /// overlay so the reveal can fade it and accessibility can raise it.
    /// Returns nil only if CoreImage cannot read the source.
    static func treated(
        _ image: UIImage,
        params: JournalBackdropParameters,
        displaySize: CGSize
    ) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        var source = CIImage(cgImage: cgImage)
            .oriented(CGImagePropertyOrientation(image.imageOrientation))

        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let longEdge = max(extent.width, extent.height)
        let downscale = min(1, maxPixelSize / longEdge)
        if downscale < 1 {
            source = source.transformed(by: CGAffineTransform(scaleX: downscale, y: downscale))
        }
        let targetExtent = source.extent.integral

        var output = source
        if params.blurStrength > 0 {
            // `scaledToFill` scale factor: the bitmap is enlarged by whichever
            // axis has to grow more. Radius is in points on screen.
            let fill = max(
                displaySize.width / targetExtent.width,
                displaySize.height / targetExtent.height
            )
            let sigmaPixels = params.blurStrength / max(fill, 0.001)
            output = output
                .clampedToExtent()
                .applyingGaussianBlur(sigma: sigmaPixels)
                .cropped(to: targetExtent)
        }

        if abs(params.saturation - 1) > 0.001 || params.blurStrength > 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = output
            controls.saturation = Float(params.saturation)
            // Blur averages highlights into midtones. A small lift undoes
            // that without painting a white veil.
            controls.brightness = params.blurStrength > 0
                ? Float(JournalBackdropShader.treatedBrightness)
                : 0
            controls.contrast = 1
            if let adjusted = controls.outputImage {
                output = adjusted
            }
        }

        guard let rendered = context.createCGImage(output, from: targetExtent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
