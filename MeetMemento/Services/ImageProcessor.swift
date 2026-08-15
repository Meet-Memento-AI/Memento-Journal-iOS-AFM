//
//  ImageProcessor.swift
//  MeetMemento
//
//  Downscales + compresses a photo before it's encrypted and stored, so a
//  full-resolution camera/library photo doesn't bloat PhotoStorage or the
//  per-card thumbnail decrypt. Run once, immediately on selection/capture —
//  not deferred to save time — so a bad image fails fast and the
//  full-resolution UIImage isn't held in memory any longer than necessary.
//

import UIKit

enum ImageProcessor {
    /// Longest edge, in points, after downscaling. Sharp enough for the
    /// journal card's 160pt-tall cover slot at Retina density.
    static let maxLongEdge: CGFloat = 1600
    /// JPEG quality — keeps typical output in the low hundreds of KB.
    static let jpegQuality: CGFloat = 0.7

    /// Downscales to `maxLongEdge` (never upscales) and JPEG-compresses.
    /// `UIImage.draw(in:)` bakes in `imageOrientation`, so no separate
    /// orientation fix-up is needed.
    static func prepareForStorage(_ image: UIImage) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longEdge = max(size.width, size.height)
        let scale = min(1, maxLongEdge / longEdge)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resized.jpegData(compressionQuality: jpegQuality)
    }
}
